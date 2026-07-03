"""
SNKRDUNK 프로모 카드 **일괄 등록** 파이프라인 (후쿠오카 1장 수동 SQL 대체).

★구조 = Scrydex 와 동일한 사상:
  Scrydex : cards.jp_scrydex_ref/en_scrydex_ref 가 "링크" → sync 가 ref 달린 카드 전체 순회.
  SNKRDUNK: card_external_refs(source='SNKRDUNK') 가 "링크" → sync 가 링크 달린 카드 전체 순회.
  이 스크립트는 그 **링크 달린 카드를 등록**하는 일반화 도구다 (1장씩 손 SQL ❌).

흐름:
  SNK 후보 CSV(메타) + 큐레이션 리스트(KO명) → 중복검사 → products/cards/card_external_refs
  일괄 생성 → 이후 daily/backfill sync 가 자동으로 전체 대상에 포함.

입력:
  --candidates  snkrdunk_missing_promo_candidates.csv (SNK 메타: title/apparel_id/set/number/image)
  --import-list snkrdunk_import_list.csv (사람 검토값: apparel_id, ko_name, product_ko_name,
                rarity_code, promo_type)  ← KO명은 자동번역 불가 → 반드시 큐레이션 필요.
  등록 대상 = import-list 에 있는 apparel_id 만 (후보에 있어도 리스트에 없으면 안 건드림).

생성 규칙 (메타몽 SVP000000173 관례):
  official_card_code = set_norm + number.zfill(9)   (예 SV-P 289 → SVP000000289)
  is_promo_exclusive=TRUE · language='KO' · super_type='POKEMON' · jp/en ref = NO_JP/NO_EN
  card_external_refs: source='SNKRDUNK', external_id=apparel_id, is_active=TRUE

중복검사(하나라도 걸리면 SKIP): official_card_code 존재 / (SNKRDUNK, apparel_id) 매핑 존재.
product: product_ko_name 로 기존 조회 → 있으면 재사용, 없으면 신규 생성.

★가격/이미지/스캐너는 이 스크립트가 직접 안 함 — DB row(products/cards/refs)만 생성하고,
  후속 액션(이미지 미러 URL, 벡터 재생성 card_id)을 출력한다. 이후:
    - 이미지: cards/v1/{card_id} 로 SNK image_url 미러 (별도)
    - 시세: backfill_snkrdunk_promo_prices.py --card-id ... → 이후 daily sync 자동
    - 스캐너: 등록된 card_id 벡터 재생성

기본 DRY_RUN. 실제 반영은 --apply.
    python import_snkrdunk_promo_cards.py                    # dry-run (전체 import-list)
    python import_snkrdunk_promo_cards.py --apply
    python import_snkrdunk_promo_cards.py --apparel 618447   # 특정 apparel 만
"""

import csv
import uuid
import argparse
from datetime import datetime

import psycopg2

from config import get_db_dsn

CAND_DEFAULT = "snkrdunk_missing_promo_candidates.csv"
LIST_DEFAULT = "snkrdunk_import_list.csv"


def gen_id(prefix):
    return f"{prefix}_" + uuid.uuid4().hex.upper()[:20]


def official_code(set_norm, number):
    return f"{set_norm}{int(number):0>9}" if str(number).strip() else None


def load_candidates(path):
    """apparel_id -> SNK 메타 dict."""
    out = {}
    with open(path, newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            aid = (r.get("snkrdunk_apparel_id") or "").strip()
            if aid:
                out[aid] = r
    return out


def load_import_list(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def dup_check(cur, official, aid):
    """(dup_reason or None)."""
    if official:
        cur.execute("SELECT COUNT(*) FROM cards WHERE official_card_code=%s", (official,))
        if cur.fetchone()[0] > 0:
            return f"official_card_code {official} 이미 존재"
    cur.execute("SELECT COUNT(*) FROM card_external_refs WHERE source='SNKRDUNK' AND external_id=%s", (str(aid),))
    if cur.fetchone()[0] > 0:
        return f"SNKRDUNK apparel_id {aid} 이미 매핑됨"
    return None


def resolve_product(cur, product_name, dry, created_cache):
    """기존 product 재사용 or 신규. (product_id, is_new)."""
    cur.execute("SELECT product_id FROM products WHERE name=%s AND language='KO' LIMIT 1", (product_name,))
    row = cur.fetchone()
    if row:
        return row[0], False
    if product_name in created_cache:      # 같은 실행 내 방금 만든 것 재사용
        return created_cache[product_name], False
    pid = gen_id("PRD")
    if not dry:
        cur.execute("""INSERT INTO products (product_id, name, series_name, language, created_at, updated_at)
                       VALUES (%s,%s,'','KO',NOW(),NOW())""", (pid, product_name))
    created_cache[product_name] = pid
    return pid, True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--candidates", default=CAND_DEFAULT)
    ap.add_argument("--import-list", default=LIST_DEFAULT)
    ap.add_argument("--apparel", help="특정 apparel_id 만")
    ap.add_argument("--hidden", action="store_true",
                    help="is_visible=FALSE 로 등록 (이미지/시세/벡터 반영 후 수동 노출)")
    args = ap.parse_args()
    dry = not args.apply

    cands = load_candidates(args.candidates)
    rows = load_import_list(args.import_list)
    if args.apparel:
        rows = [r for r in rows if (r.get("apparel_id") or "").strip() == args.apparel]

    conn = psycopg2.connect(get_db_dsn())
    conn.autocommit = False
    log = print
    log(f"=== SNKRDUNK 프로모 등록 {'[DRY-RUN]' if dry else '[APPLY]'} · import-list {len(rows)}건 ===")

    created, skipped, followups = 0, 0, []
    with conn.cursor() as cur:
        product_cache = {}
        for r in rows:
            aid = (r.get("apparel_id") or "").strip()
            ko_name = (r.get("ko_name") or "").strip()
            product_name = (r.get("product_ko_name") or "").strip()
            rarity = (r.get("rarity_code") or "PR").strip()
            promo_type = (r.get("promo_type") or "MISC").strip()
            meta = cands.get(aid)

            if not aid or not ko_name or not product_name:
                log(f"  [SKIP] apparel={aid} — ko_name/product 미기입(큐레이션 필요)"); skipped += 1; continue
            if not meta:
                log(f"  [SKIP] apparel={aid} — 후보 CSV에 SNK 메타 없음"); skipped += 1; continue

            set_norm = meta["set_norm"]; number = meta["number"]
            official = official_code(set_norm, number)
            image_url = meta.get("snkrdunk_image_url", "")
            snk_url = f"https://snkrdunk.com/v1/apparels/{aid}"

            reason = dup_check(cur, official, aid)
            if reason:
                log(f"  [DUP-SKIP] {ko_name} (aid={aid}) — {reason}"); skipped += 1; continue

            pid_override = (r.get("product_id") or "").strip()
            if pid_override:
                # 공유 product 직접 지정 (예: JP_PROMO_EXCLUSIVE — 일본 독점 프로모 공유, 새 product 생성 금지)
                cur.execute("SELECT product_id FROM products WHERE product_id=%s", (pid_override,))
                if not cur.fetchone():
                    log(f"  [SKIP] {ko_name} — product_id {pid_override} 미존재"); skipped += 1; continue
                pid, pnew = pid_override, False
            else:
                pid, pnew = resolve_product(cur, product_name, dry, product_cache)
            cid = gen_id("CRD")
            log(f"  [CREATE] {ko_name} | {official} | {rarity}/{promo_type} | product {'NEW ' if pnew else '재사용 '}{pid}")
            log(f"           card_id={cid} · SNKRDUNK ref={aid} · image={image_url}")

            if not dry:
                cur.execute("""
                    INSERT INTO cards
                        (card_id, product_id, official_card_code, name, collection_number,
                         rarity_code, language, super_type, jp_scrydex_ref, en_scrydex_ref,
                         is_promo_exclusive, promo_type, image_url, local_image_path,
                         is_visible, created_at, updated_at)
                    VALUES (%s,%s,%s,%s,NULL,%s,'KO','POKEMON','NO_JP','NO_EN',
                            TRUE,%s,NULL,NULL,%s,NOW(),NOW())
                """, (cid, pid, official, ko_name, rarity, promo_type, not args.hidden))
                cur.execute("""
                    INSERT INTO card_external_refs (card_id, source, external_id, external_url, is_active)
                    VALUES (%s,'SNKRDUNK',%s,%s,TRUE)
                """, (cid, str(aid), snk_url))
            created += 1
            followups.append((cid, ko_name, image_url))

    if dry:
        conn.rollback()
        log(f"\n=== DRY-RUN: 생성 예정 {created} · 스킵 {skipped} (write 0) ===")
    else:
        conn.commit()
        log(f"\n=== APPLY 완료: 생성 {created} · 스킵 {skipped} ===")
    conn.close()

    if followups:
        log("\n── 후속 액션 (등록된 카드) ──")
        for cid, name, img in followups:
            log(f"  · {name} [{cid}]")
            log(f"      이미지 미러: {img} → S3 cards/v1/{cid}")
            log(f"      시세 백필  : python backfill_snkrdunk_promo_prices.py --card-id {cid} --apply")
            log(f"      스캐너     : {cid} 벡터 재생성")
        log("  (그 다음부터는 daily sync 가 이 카드들을 자동 순회)")


if __name__ == "__main__":
    main()
