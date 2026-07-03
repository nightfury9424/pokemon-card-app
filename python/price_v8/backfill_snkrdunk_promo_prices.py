"""
SNKRDUNK-only 프로모 **과거 차트 백필** (일일 sync 와 별도).

sync_snkrdunk_promo_prices.py = 매일 오늘자 median 1점.
이 스크립트 = SNKRDUNK sales-history 전체 페이지를 **실제 체결일 기준 일자별 median** 으로
과거 시계열을 채운다 (차트용). traded_at = 실제 체결일(정오), now 아님.

등급별(A→RAW, PSA10→GRADED/PSA/10, PSA9→GRADED/PSA/9) 일자별 median 을
  source='SNKRDUNK'      (raw_price=median_jpy, raw_currency='JPY')
  source='KO_ESTIMATED'  (RAW 일자별 median 만 — 헤드라인 차트 koLine 용)
로 적재.

멱등: price_snapshot_id 가 랜덤 UUID 라 ON CONFLICT 로는 내용 중복을 못 막는다 →
INSERT 전에 (card_id, source, card_status, grade_value, traded_at::date) 존재 여부를
확인하고 이미 있는 날짜는 건너뛴다 (price_scrydex.get_existing_dates 패턴).

기본 DRY_RUN. 실제 반영은 --apply. 상세 문서: 노출은 후속 백엔드(차트 source 파라미터화) 필요.

    python backfill_snkrdunk_promo_prices.py --card-id CRD_xxx           # dry-run
    python backfill_snkrdunk_promo_prices.py --card-id CRD_xxx --apply
"""

import re
import uuid
import time
import argparse
import statistics
from collections import defaultdict
from datetime import datetime, timezone, timedelta

import requests
import psycopg2

from config import get_db_dsn

SALES_EP = "https://snkrdunk.com/v1/apparels/{aid}/sales-history?size_id=0&page={page}&per_page={per}"
HEADERS = {"accept": "application/json", "user-agent": "Mozilla/5.0"}
GRADE_MAP = {
    "A":     ("RAW",    None,  None),
    "PSA10": ("GRADED", "PSA", "10"),
    "PSA9":  ("GRADED", "PSA", "9"),
}
MAX_PAGES = 60          # 전체 히스토리 (per_page=50 → 최대 3000건)
PER_PAGE = 50
FALLBACK_JPY_KRW = 9.5
KST = timezone(timedelta(hours=9))


def log(*a):
    print(*a, flush=True)


def parse_date(s, now):
    """상대/절대 날짜 → date. 실패 시 None."""
    s = (s or "").strip()
    for pat, unit in ((r"(\d+)分前", "m"), (r"(\d+)時間前", "h"), (r"(\d+)日前", "d")):
        m = re.match(pat, s)
        if m:
            n = int(m.group(1))
            dt = now - timedelta(**{"m": {"minutes": n}, "h": {"hours": n}, "d": {"days": n}}[unit])
            return dt.date()
    m = re.match(r"(\d{4})/(\d{2})/(\d{2})", s)
    if m:
        return datetime(int(m.group(1)), int(m.group(2)), int(m.group(3))).date()
    return None


def load_jpy_krw(conn):
    with conn.cursor() as cur:
        cur.execute("""SELECT price FROM price_snapshots
                       WHERE card_id='exchange_rate_jpy' AND source='SYSTEM'
                       ORDER BY collected_at DESC LIMIT 1""")
        row = cur.fetchone()
    # ★환율은 ×100 정수 저장(954=9.54) → ÷100 (price_scrydex 동일).
    return float(row[0]) / 100.0 if row and row[0] and float(row[0]) > 0 else FALLBACK_JPY_KRW


def get_targets(conn, card_id):
    with conn.cursor() as cur:
        cur.execute("""SELECT c.card_id, c.name, e.external_id, e.external_url
                       FROM cards c JOIN card_external_refs e
                         ON e.card_id=c.card_id AND e.source='SNKRDUNK' AND e.is_active=TRUE
                       WHERE c.is_promo_exclusive=TRUE AND c.card_id=%s""", (card_id,))
        return cur.fetchall()


def existing_dates(conn, card_id, source, cstatus, company, grade):
    """이미 적재된 날짜 집합 (멱등 스킵용)."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT traded_at::date FROM price_snapshots
            WHERE card_id=%s AND source=%s AND card_status=%s
              AND grading_company IS NOT DISTINCT FROM %s
              AND grade_value    IS NOT DISTINCT FROM %s
        """, (card_id, source, cstatus, company, grade))
        return {r[0] for r in cur.fetchall()}


def fetch_all(aid, now):
    """전체 페이지 → grade -> {date: [jpy,...]}."""
    by = {g: defaultdict(list) for g in GRADE_MAP}
    total = 0
    for page in range(1, MAX_PAGES + 1):
        try:
            r = requests.get(SALES_EP.format(aid=aid, page=page, per=PER_PAGE),
                             headers=HEADERS, timeout=15)
            if r.status_code != 200:
                log(f"  [WARN] HTTP {r.status_code} page={page} → 중단"); break
            hist = r.json().get("history", [])
        except Exception as e:
            log(f"  [WARN] fetch 실패 page={page}: {e} → 중단"); break
        if not hist:
            break
        total += len(hist)
        for h in hist:
            c = h.get("condition")
            d = parse_date(h.get("date", ""), now)
            if c in by and d and h.get("price"):
                by[c][d].append(int(h["price"]))
        time.sleep(1.5)
    return by, total


def insert_snap(cur, card_id, source, price_krw, cstatus, company, grade,
                aid, url, title, raw_jpy, traded_at):
    sid = "SNAP_" + uuid.uuid4().hex.upper()[:20]
    cur.execute("""
        INSERT INTO price_snapshots
            (price_snapshot_id, card_id, source, price, card_status,
             grading_company, grade_value, source_item_id, source_url, title,
             raw_price, raw_currency, traded_at, collected_at, created_at)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW(),NOW())
    """, (sid, card_id, source, price_krw, cstatus, company, grade,
          str(aid), url, title, raw_jpy, ("JPY" if raw_jpy is not None else None), traded_at))


def round10(v):
    return int(round(v / 10.0)) * 10


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--card-id", required=True)
    args = ap.parse_args()
    dry = not args.apply

    conn = psycopg2.connect(get_db_dsn())
    conn.autocommit = False
    now = datetime.now(KST).replace(tzinfo=None)
    jpy_krw = load_jpy_krw(conn)
    targets = get_targets(conn, args.card_id)
    if not targets:
        log("대상 없음 (매핑/promo 플래그 확인)"); return
    log(f"=== SNKRDUNK 백필 {'[DRY-RUN]' if dry else '[APPLY]'} · JPY→KRW {jpy_krw} ===")

    planned = 0
    for card_id, name, aid, url in targets:
        by, total = fetch_all(aid, now)
        log(f"\n▶ {name} (aid={aid}) 총 체결 {total}건 수집")
        for g, (cstatus, company, grade) in GRADE_MAP.items():
            days = by[g]
            if not days:
                log(f"   {g:6s}: 체결 0 → 스킵"); continue
            have = existing_dates(conn, card_id, "SNKRDUNK", cstatus, company, grade)
            dmin, dmax = min(days), max(days)
            new_days = [d for d in sorted(days) if d not in have]
            log(f"   {g:6s}: 체결일 {len(days)}일 ({dmin}~{dmax}) · 신규 {len(new_days)}일 · 기존 {len(have)}일")
            if not dry:
                with conn.cursor() as cur:
                    for d in new_days:
                        med = statistics.median(days[d])
                        krw = round10(med * jpy_krw)
                        ta = datetime(d.year, d.month, d.day, 12, 0)
                        title = f"SNKRDUNK {g} daily median n={len(days[d])} JPY{int(med)}"
                        insert_snap(cur, card_id, "SNKRDUNK", krw, cstatus, company, grade,
                                    aid, url, title, med, ta)
                        if g == "A":
                            have_ko = existing_dates(conn, card_id, "KO_ESTIMATED", "RAW", None, None)
                            if d not in have_ko:
                                insert_snap(cur, card_id, "KO_ESTIMATED", krw, "RAW", None, None,
                                            aid, url, f"SNKRDUNK RAW->KO daily n={len(days[d])}", None, ta)
            planned += len(new_days)

    if dry:
        conn.rollback()
        log(f"\n=== DRY-RUN: 예상 신규 insert 일수 합 {planned} (write 0) ===")
        log("    (실제 insert 는 grade별 SNKRDUNK + RAW의 KO_ESTIMATED 포함해 더 많음)")
    else:
        conn.commit()
        log(f"\n=== APPLY 완료 ===")
    conn.close()


if __name__ == "__main__":
    main()
