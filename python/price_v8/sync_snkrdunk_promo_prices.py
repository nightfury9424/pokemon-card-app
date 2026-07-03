"""
SNKRDUNK-only 프로모 KO 시세 **일일 축적 동기화** (A / PSA10 / PSA9 3등급).

★설계 원칙 = scrydex 동기화(price_scrydex.save_history)와 **동일한 append-only 축적**:
  - 실제 체결일별 median 을 그 날짜(traded_at=실제 체결일)로 저장
  - 이미 저장된 날짜는 건너뛴다 (get_existing_dates dedup) → **덮어쓰지 않고 축적**
  - 절대 DELETE 안 함 (rolling median 덮어쓰기 ❌ — 그건 축적이 아니라 평활 오염)
  daily = backfill 과 같은 로직, 최근 페이지만. (backfill_snkrdunk_promo_prices.py = 전체 페이지)

저장 관례 (scrydex·KREAM 동일):
  RAW   : card_status='RAW'   grading_company=NULL grade_value=NULL
  PSA10 : card_status='GRADED' grading_company='PSA' grade_value='10'
  PSA9  : card_status='GRADED' grading_company='PSA' grade_value='9'
소스:
  source='SNKRDUNK'      3등급 실체결 일별 median (raw_price=median_jpy, raw_currency='JPY')
  source='KO_ESTIMATED'  RAW 일별 median (헤드라인 예상가 — 앱 getDisplayPrice 가 최신점 읽음)

★v6 / scrydex sync / rarity ladder / sanity cap 경로 절대 안 탐 (설계 보장):
  NO_JP/NO_EN + is_promo_exclusive=TRUE → 4중 제외 (상세: RESULTS.md / chart_exposure_design.md)
  ladder 강제 없음(후쿠오카 RAW>PSA9 실측 그대로).

접근 실패(1페이지 에러/0건) → write 0, 아무것도 안 건드림.
기본 DRY_RUN. 실제 반영은 --apply.

    python sync_snkrdunk_promo_prices.py                     # dry-run
    python sync_snkrdunk_promo_prices.py --apply            # prod 반영
    python sync_snkrdunk_promo_prices.py --card-id CRD_xxx  # 특정 카드
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
MAX_PAGES = 8            # 최근분 (daily). 새로 생긴 체결일만 append 되므로 이 정도면 충분.
PER_PAGE = 50
FALLBACK_JPY_KRW = 9.5
KST = timezone(timedelta(hours=9))


def log(*a):
    print(*a, flush=True)


def parse_date(s, now):
    """상대/절대 체결일 → date. 실패 시 None."""
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
    # ★환율은 price_snapshots 에 ×100 정수로 저장됨(예 954=9.54). price_scrydex 와 동일하게 ÷100.
    with conn.cursor() as cur:
        cur.execute("""SELECT price FROM price_snapshots
                       WHERE card_id='exchange_rate_jpy' AND source='SYSTEM'
                       ORDER BY collected_at DESC LIMIT 1""")
        row = cur.fetchone()
    if row and row[0] and float(row[0]) > 0:
        return float(row[0]) / 100.0
    log(f"  [WARN] DB 환율 없음 → fallback {FALLBACK_JPY_KRW}")
    return FALLBACK_JPY_KRW


def get_targets(conn, card_id=None):
    with conn.cursor() as cur:
        q = """SELECT c.card_id, c.name, e.external_id, e.external_url
               FROM cards c JOIN card_external_refs e
                 ON e.card_id=c.card_id AND e.source='SNKRDUNK' AND e.is_active=TRUE
               WHERE c.is_promo_exclusive=TRUE"""
        params = []
        if card_id:
            q += " AND c.card_id=%s"; params.append(card_id)
        q += " ORDER BY c.card_id"
        cur.execute(q, params)
        return cur.fetchall()


def existing_dates(conn, card_id, source, cstatus, company, grade):
    """이미 축적된 날짜 집합 (append-only dedup — scrydex get_existing_dates 와 동일 역할)."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT traded_at::date FROM price_snapshots
            WHERE card_id=%s AND source=%s AND card_status=%s
              AND grading_company IS NOT DISTINCT FROM %s
              AND grade_value    IS NOT DISTINCT FROM %s
        """, (card_id, source, cstatus, company, grade))
        return {r[0] for r in cur.fetchall()}


def fetch_recent(aid, now):
    """최근 페이지 → grade -> {date: [jpy,...]}. (grades, fetch_ok)."""
    by = {g: defaultdict(list) for g in GRADE_MAP}
    total = 0
    page1_ok = False
    for page in range(1, MAX_PAGES + 1):
        try:
            r = requests.get(SALES_EP.format(aid=aid, page=page, per=PER_PAGE),
                             headers=HEADERS, timeout=15)
            if r.status_code != 200:
                log(f"  [WARN] HTTP {r.status_code} page={page}"); break
            hist = r.json().get("history", [])
        except Exception as e:
            log(f"  [WARN] fetch 실패 page={page}: {e}"); break
        if page == 1:
            page1_ok = True
        if not hist:
            break
        total += len(hist)
        for h in hist:
            c = h.get("condition")
            d = parse_date(h.get("date", ""), now)
            if c in by and d and h.get("price"):
                by[c][d].append(int(h["price"]))
        time.sleep(1.5)
    return by, (page1_ok and total > 0)


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
    ap.add_argument("--card-id")
    args = ap.parse_args()
    dry = not args.apply

    conn = psycopg2.connect(get_db_dsn())
    conn.autocommit = False
    now = datetime.now(KST).replace(tzinfo=None)
    jpy_krw = load_jpy_krw(conn)
    targets = get_targets(conn, args.card_id)
    log(f"=== SNKRDUNK 프로모 축적 동기화 {'[DRY-RUN]' if dry else '[APPLY]'} "
        f"대상 {len(targets)}장 · JPY→KRW {jpy_krw} ===")

    total_new = 0
    for card_id, name, aid, url in targets:
        by, fetch_ok = fetch_recent(aid, now)
        log(f"\n▶ {name} (aid={aid})")
        if not fetch_ok:
            log("   [SKIP-ALL] fetch 실패 → write 0, 손 안 댐")
            continue
        for g, (cstatus, company, grade) in GRADE_MAP.items():
            days = by[g]
            if not days:
                log(f"   {g:6s}: 최근 체결 0 → 스킵")
                continue
            have = existing_dates(conn, card_id, "SNKRDUNK", cstatus, company, grade)
            new_days = [d for d in sorted(days) if d not in have]
            if not new_days:
                log(f"   {g:6s}: 신규 체결일 0 (이미 축적됨)")
                continue
            log(f"   {g:6s}: 신규 체결일 {len(new_days)}일 append "
                f"({new_days[0]}~{new_days[-1]})")
            if not dry:
                with conn.cursor() as cur:
                    have_ko = (existing_dates(conn, card_id, "KO_ESTIMATED", "RAW", None, None)
                               if g == "A" else set())
                    for d in new_days:
                        med = statistics.median(days[d])
                        krw = round10(med * jpy_krw)
                        ta = datetime(d.year, d.month, d.day, 12, 0)
                        title = f"SNKRDUNK {g} daily median n={len(days[d])} JPY{int(med)}"
                        insert_snap(cur, card_id, "SNKRDUNK", krw, cstatus, company, grade,
                                    aid, url, title, med, ta)
                        if g == "A" and d not in have_ko:
                            insert_snap(cur, card_id, "KO_ESTIMATED", krw, "RAW", None, None,
                                        aid, url, f"SNKRDUNK RAW->KO daily n={len(days[d])}", None, ta)
            total_new += len(new_days)

    if dry:
        conn.rollback()
        log(f"\n=== DRY-RUN 완료: 신규 append 예상 (등급별 일수 합) {total_new} (write 0) ===")
    else:
        conn.commit()
        log(f"\n=== APPLY 완료: 신규 append {total_new} ===")
    conn.close()


if __name__ == "__main__":
    main()
