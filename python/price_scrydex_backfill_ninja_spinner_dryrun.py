#!/usr/bin/env python3
"""
price_scrydex_backfill_ninja_spinner_dryrun.py
==============================================
닌자스피너 신규 27장 한정 Scrydex historical fetch DRY-RUN (INSERT X).

[배경]
2026-05-30 닌자스피너 master 27장 INSERT (SAR 6 + AR 11 + SR 10) +
S3 이미지 27장 업로드 완료. 다음 = SCRYDEX_JP raw + KO_ESTIMATED 시계열
backfill — 단, 사용자 명시 "dry-run 먼저, INSERT 하지 마".

[정책]
- product_id = PRD_156BB71C4F5A41C39521 한정
- jp_scrydex_ref 명시 27개 (095/109/111 보류 + 도구 6장 제외)
- 기존 RR 8 + MUR 1 = 9장은 이미 snapshot 보유 → 건드리지 않음
- save_history() / insert_snapshot() / KO_ESTIMATE_REFRESH 호출 절대 X
- fetch_html + parse_history 만 호출, 결과 print

[사용]
  docker exec pokefolio-back python3 /tmp/price_scrydex_backfill_ninja_spinner_dryrun.py
  → 출력 보고 사용자 GO 시그널 → 정식 backfill cycle 별 작성
"""
from __future__ import annotations
import os
import sys

sys.path.insert(0, "/app/python")
from price_scrydex import (
    get_conn, fetch_exchange_rates, fetch_html, parse_history, safe_print,
    SLEEP, FALLBACK_USD_KRW, FALLBACK_JPY_KRW,
)
import time

TARGET_PRODUCT_ID = "PRD_156BB71C4F5A41C39521"
TARGET_JP_REFS = [
    # SAR 6 (col 114-119)
    "m4_ja-114", "m4_ja-115", "m4_ja-116", "m4_ja-117", "m4_ja-118", "m4_ja-119",
    # AR 11 (col 084-094, 095 보류)
    "m4_ja-84",  "m4_ja-85",  "m4_ja-86",  "m4_ja-87",  "m4_ja-88",  "m4_ja-89",
    "m4_ja-90",  "m4_ja-91",  "m4_ja-92",  "m4_ja-93",  "m4_ja-94",
    # SR 10 (col 096-103 + 108 + 110)
    "m4_ja-96",  "m4_ja-97",  "m4_ja-98",  "m4_ja-99",  "m4_ja-100",
    "m4_ja-101", "m4_ja-102", "m4_ja-103", "m4_ja-108", "m4_ja-110",
]

# JP rarity coefficient (BOOTSTRAP_NAVER_DAANGN, scope=RARITY, coef_type=JP)
JP_COEF = {
    "SAR": 0.376892,
    "MUR": 0.487134,
    "SR":  0.388629,
    "AR":  0.535789,
    "HR":  0.432255,
    "UR":  0.491811,
}
MARKET_ADJ = 1.065  # 우리 시뮬레이션 검증 — 기존 MUR 메가개굴닌자 EX 99.96% 정확


def fetch_target_cards(conn):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT card_id, collection_number, rarity_code, name, jp_scrydex_ref
            FROM cards
            WHERE product_id = %s
              AND language = 'KO'
              AND is_visible = TRUE
              AND jp_scrydex_ref = ANY(%s)
            ORDER BY CAST(regexp_replace(collection_number, '/.*', '') AS int)
        """, (TARGET_PRODUCT_ID, TARGET_JP_REFS))
        return cur.fetchall()


def existing_snapshots(conn, card_id, source):
    """이미 들어간 snapshot 날짜 set (중복 방지 검증용)."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DATE(traded_at) FROM price_snapshots
            WHERE card_id=%s AND source=%s AND card_status='RAW'
        """, (card_id, source))
        return {row[0] for row in cur.fetchall()}


def main():
    print("=" * 80)
    print("닌자스피너 Scrydex backfill DRY-RUN (INSERT 0)")
    print("=" * 80)

    usd_krw, jpy_krw = fetch_exchange_rates()
    print(f"환율    : USD/KRW = {usd_krw:.0f}, JPY/KRW = {jpy_krw:.2f}")
    print(f"산식    : SCRYDEX_JP = JPY × {jpy_krw:.2f}  /  KO_EST = SCRYDEX_JP × jp_coef × {MARKET_ADJ}")
    print()

    conn = get_conn()
    cards = fetch_target_cards(conn)
    print(f"DB 매칭 : {len(cards)}장 (기대 27)")
    print()

    if len(cards) != 27:
        print(f"⚠️ WARNING: 27장 기대 vs {len(cards)}장 매칭 — 검토 필요")

    print(f"{'#':>2} {'col':>3} {'rar':>3}  {'name':<18} {'jp_ref':<14} {'oldest':<12} {'latest':<12} {'raw_n':>5} {'ko_n':>5} {'last_JPY':>10} {'last_JP_KRW':>12} {'sim_KO_KRW':>11} {'existing':>8}  status")
    print("-" * 165)

    total_raw_snapshots = 0
    total_existing = 0
    success = 0
    failures = []

    for i, (card_id, col, rarity, name, jp_ref) in enumerate(cards, 1):
        col_int = col.split("/")[0]
        short_name = name[:17] if len(name) > 18 else name

        # 1) fetch
        html = fetch_html(jp_ref)
        if not html:
            print(f"{i:>2} {col_int:>3} {rarity:>3}  {short_name:<18} {jp_ref:<14} {'FETCH_FAIL':<50}")
            failures.append((card_id, jp_ref, "fetch_html None"))
            continue

        # 2) parse
        try:
            raw_nm, psa10, psa9, raw_is_krw, raw_is_jpy = parse_history(html, is_jp=True, jpy_krw=jpy_krw)
        except Exception as e:
            print(f"{i:>2} {col_int:>3} {rarity:>3}  {short_name:<18} {jp_ref:<14} PARSE_FAIL: {e}")
            failures.append((card_id, jp_ref, f"parse_history: {e}"))
            continue

        if not raw_nm:
            print(f"{i:>2} {col_int:>3} {rarity:>3}  {short_name:<18} {jp_ref:<14} NO_RAW_DATA  (raw_is_krw={raw_is_krw} raw_is_jpy={raw_is_jpy})")
            failures.append((card_id, jp_ref, "raw_nm empty"))
            continue

        # 3) 통계
        oldest = raw_nm[0][0]
        latest_date = raw_nm[-1][0]
        latest_price = raw_nm[-1][1]  # raw_is_jpy=True 면 JPY 원값
        raw_n = len(raw_nm)
        ko_n = raw_n  # SCRYDEX_JP raw : KO_ESTIMATED = 1:1 매핑 (KO_ESTIMATE_REFRESH 가 batch 처리)

        # 4) 산식 적용
        if raw_is_jpy:
            scrydex_jp_krw = int(latest_price * jpy_krw)
        elif raw_is_krw:
            scrydex_jp_krw = int(latest_price)
        else:
            scrydex_jp_krw = int(latest_price * usd_krw)

        coef = JP_COEF.get(rarity, 0.40)
        sim_ko = int(scrydex_jp_krw * coef * MARKET_ADJ)

        # 5) 기존 snapshot 중복 방지 검증
        existing = existing_snapshots(conn, card_id, "SCRYDEX_JP")
        existing_overlap = sum(1 for d, _ in raw_nm if d in existing)
        net_new = raw_n - existing_overlap

        total_raw_snapshots += net_new
        total_existing += existing_overlap

        print(f"{i:>2} {col_int:>3} {rarity:>3}  {short_name:<18} {jp_ref:<14} {oldest:<12} {latest_date:<12} {raw_n:>5} {ko_n:>5} {int(latest_price):>10,} {scrydex_jp_krw:>12,} {sim_ko:>11,} {existing_overlap:>8}  OK")
        success += 1

        time.sleep(SLEEP)

    conn.close()

    print()
    print("=" * 80)
    print(f"전체           : {len(cards)}장")
    print(f"성공           : {success}")
    print(f"실패           : {len(failures)}")
    print(f"SCRYDEX_JP 신규 snapshot 예정 : {total_raw_snapshots} 건  (중복 {total_existing} 건 제외)")
    print(f"KO_ESTIMATED   예정 (1:1)     : {total_raw_snapshots} 건")
    print()
    if failures:
        print("FAILURES:")
        for cid, ref, err in failures:
            print(f"  {cid[:24]} ({ref}): {err}")
        print()
    print("[INSERT 0건 — INSERT/REFRESH 일체 호출 안 함]")
    print()
    print("결과 OK 시 → 정식 backfill 진행 (price_scrydex_backfill_ninja_spinner_apply.py 별 작성 + GO)")


if __name__ == "__main__":
    main()
