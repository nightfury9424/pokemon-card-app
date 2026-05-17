"""
scrydex 히스토리 배치 수집 (RAW NM + PSA 10/9)

초기 백필:
    python price_scrydex.py --backfill

일별 동기화 (최근 3일치만):
    python price_scrydex.py

특정 카드만:
    python price_scrydex.py --card-id CRD_xxx

병렬 스레드 수 (기본 8):
    python price_scrydex.py --backfill --workers 12
"""

import re
import time
import argparse
import uuid
import statistics
from datetime import datetime, timedelta, timezone, date
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
from typing import Optional

import psycopg2
import requests

from config import DB_CONFIG, HEADERS

try:
    import price_ebay
    _EBAY_GUARD = True
except ImportError:
    _EBAY_GUARD = False

BASE_URL = "https://scrydex.com/pokemon/cards/_/"
FALLBACK_USD_KRW = 1400
FALLBACK_JPY_KRW = 9.5
SLEEP = 1.2  # 요청 간격 (초)
KO_ESTIMATE_REFRESH_URL = "http://localhost:8080/api/prices/admin/refresh-ko-estimates"

_print_lock = threading.Lock()


def safe_print(*args, **kwargs):
    with _print_lock:
        print(*args, **kwargs, flush=True)


# ─── 환율 (REFACTOR_2026-05-12.md 2-① DB 단일화) ────────────────────────────

def _load_exchange_rates_from_db(conn):
    """오늘자 환율을 price_snapshots SYSTEM에서 조회. 둘 다 있을 때만 (usd, jpy) 반환."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT card_id, price FROM price_snapshots
            WHERE card_id IN ('exchange_rate_usd', 'exchange_rate_jpy')
              AND source = 'SYSTEM'
              AND DATE(traded_at) = CURRENT_DATE
            ORDER BY traded_at DESC
        """)
        rates = {r[0]: r[1] / 100.0 for r in cur.fetchall()}
    if 'exchange_rate_usd' in rates and 'exchange_rate_jpy' in rates:
        return rates['exchange_rate_usd'], rates['exchange_rate_jpy']
    return None


def _save_exchange_rate_to_db(conn, card_id, value):
    """오늘자 환율 저장. 이미 있거나 동시 INSERT race로 unique violation 발생 시 무시.
    Hotfix-D (Codex CRITICAL #4): Java/Python 동시 INSERT 안전 보장.
    """
    import psycopg2
    with conn.cursor() as cur:
        cur.execute("""
            SELECT 1 FROM price_snapshots
            WHERE card_id = %s AND source = 'SYSTEM' AND DATE(traded_at) = CURRENT_DATE
            LIMIT 1
        """, (card_id,))
        if cur.fetchone():
            return
        try:
            cur.execute("""
                INSERT INTO price_snapshots
                  (price_snapshot_id, card_id, source, price, card_status, traded_at, collected_at)
                VALUES (%s, %s, 'SYSTEM', %s, 'RAW', NOW(), NOW())
            """, (uuid.uuid4().hex[:32], card_id, int(round(value * 100))))
            conn.commit()
        except psycopg2.errors.UniqueViolation:
            conn.rollback()
            safe_print(f"[ExchangeRate] {card_id} 동시 저장 race — 다른 프로세스가 박음, 무시")
        except Exception:
            conn.rollback()
            raise


def fetch_exchange_rates():
    """우선순위: DB 오늘자 → 외부 API + DB 저장 → fallback(메모리만).
    외부 API 실패 시 fallback은 DB에 박지 않음 — Hotfix-A (Codex CRITICAL #3).
    """
    conn = get_conn()
    try:
        cached = _load_exchange_rates_from_db(conn)
        if cached is not None:
            safe_print(f"환율(DB): 1 USD = {cached[0]:.2f} KRW, 1 JPY = {cached[1]:.4f} KRW")
            return cached

        usd_krw = FALLBACK_USD_KRW
        jpy_krw = FALLBACK_JPY_KRW
        api_ok = False
        try:
            resp = requests.get("https://open.er-api.com/v6/latest/USD", timeout=10)
            data = resp.json()
            rates = data.get("rates", {})
            if rates.get("KRW") and rates.get("JPY"):
                usd_krw = float(rates["KRW"])
                jpy_krw = float(rates["KRW"]) / float(rates["JPY"])
                api_ok = True
        except Exception as e:
            safe_print(f"[WARN] 환율 외부 조회 실패: {e}")

        if api_ok:
            _save_exchange_rate_to_db(conn, 'exchange_rate_usd', usd_krw)
            _save_exchange_rate_to_db(conn, 'exchange_rate_jpy', jpy_krw)
            safe_print(f"환율(외부+DB 저장): 1 USD = {usd_krw:.2f} KRW, 1 JPY = {jpy_krw:.4f} KRW")
        else:
            safe_print(f"환율(fallback, DB 저장 안 함): 1 USD = {usd_krw:.2f} KRW, 1 JPY = {jpy_krw:.4f} KRW")
        return usd_krw, jpy_krw
    finally:
        conn.close()


# ─── DB ──────────────────────────────────────────────────────────────────────

def get_conn():
    return psycopg2.connect(**DB_CONFIG)


def get_mapped_cards(conn):
    """EN 또는 JP scrydex ref가 있는 카드 목록 (KO 정발 + 프로모 독점 포함)"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT card_id, en_scrydex_ref, jp_scrydex_ref, rarity_code, is_promo_exclusive
            FROM cards
            WHERE (language = 'KO' OR is_promo_exclusive = TRUE)
              AND (
                (en_scrydex_ref IS NOT NULL AND en_scrydex_ref NOT LIKE 'NO_%' AND en_scrydex_ref != '')
                OR
                (jp_scrydex_ref IS NOT NULL AND jp_scrydex_ref NOT LIKE 'NO_%' AND jp_scrydex_ref != '')
              )
            ORDER BY card_id
        """)
        return cur.fetchall()


def get_existing_dates(conn, card_id, source, card_status, grade_value=None):
    """이미 DB에 있는 날짜 집합 (중복 방지)"""
    with conn.cursor() as cur:
        if grade_value:
            cur.execute("""
                SELECT DISTINCT traded_at::date
                FROM price_snapshots
                WHERE card_id = %s AND source = %s AND card_status = %s
                  AND grading_company = 'PSA' AND grade_value = %s
            """, (card_id, source, card_status, grade_value))
        else:
            cur.execute("""
                SELECT DISTINCT traded_at::date
                FROM price_snapshots
                WHERE card_id = %s AND source = %s AND card_status = %s
                  AND grading_company IS NULL
            """, (card_id, source, card_status))
        return {row[0].isoformat() for row in cur.fetchall()}


def insert_snapshot(cur, card_id, source, price_krw, card_status, date_str,
                    grading_company=None, grade_value=None,
                    raw_price=None, raw_currency=None):
    snap_id = str(uuid.uuid4()).replace("-", "")[:32]
    traded_at = datetime.strptime(date_str, "%Y-%m-%d").replace(
        hour=12, tzinfo=timezone.utc)
    cur.execute("""
        INSERT INTO price_snapshots
          (price_snapshot_id, card_id, source, price,
           card_status, grading_company, grade_value,
           raw_price, raw_currency,
           traded_at, collected_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT DO NOTHING
    """, (snap_id, card_id, source, price_krw, card_status,
          grading_company, grade_value, raw_price, raw_currency, traded_at))


# ─── 파싱 ─────────────────────────────────────────────────────────────────────

def fetch_html(ref):
    url = BASE_URL + ref
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        if resp.status_code != 200:
            return None
        return resp.text
    except Exception as e:
        safe_print(f"  [WARN] fetch 실패: {ref} — {e}")
        return None


def parse_point_array(array_str):
    """[["2026-04-11",30.05],["2026-04-12",null],...] → [(date, price), ...]"""
    pat = re.compile(r'\["(\d{4}-\d{2}-\d{2})",\s*(null|\d+\.?\d*)\]')
    points = []
    for m in pat.finditer(array_str):
        date = m.group(1)
        val = m.group(2)
        if val != "null":
            points.append((date, float(val)))
    return points


def parse_series_by_name(data, name):
    """배열에서 특정 name의 series 파싱"""
    escaped = re.escape(name)
    pat = re.compile(
        r'"name":\s*"' + escaped + r'"[^}]*?"data":\s*(\[\[.*?\]\])',
        re.DOTALL)
    m = pat.search(data)
    if not m:
        return []
    return parse_point_array(m.group(1))


def parse_raw_nm_series(data):
    """
    RAW NM series 파싱.
    우선순위: name="Near Mint" → name="NM" → 단일 series인 경우만 첫 번째 사용.
    """
    for name in ("Near Mint", "NM"):
        pts = parse_series_by_name(data, name)
        if pts:
            return pts

    # 단일 series인 경우만 첫 번째 series 사용
    series_count = len(re.findall(r'"name":\s*"', data))
    if series_count <= 1:
        m = re.search(r'"data":\s*(\[\[.*?\]\])', data, re.DOTALL)
        if m:
            return parse_point_array(m.group(1))

    return []


def parse_prices_section_nm(html, is_jp):
    """
    Prices 섹션 Near Mint 현재가 파싱 (차트 없는 카드 폴백).
    JP: ¥900,000 → (today, jpy_price), 없으면 $50.21 → (today, usd_price)
    EN: $50.21  → (today, usd_price)
    반환: (today_str, raw_value, is_jpy)  or None
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    if is_jp:
        # ¥900,000 형태
        m = re.search(r'Near Mint[^¥￥]{0,400}[¥￥]([\d,]+)', html, re.DOTALL)
        if m:
            try:
                jpy = float(m.group(1).replace(",", ""))
                return (today, jpy, True)
            except ValueError:
                pass
        # scrydex는 JP 카드도 USD로 표시하는 경우가 있음
        m = re.search(r'Near Mint[^$]{0,400}\$([\d,]+\.?\d*)', html, re.DOTALL)
        if m:
            try:
                usd = float(m.group(1).replace(",", ""))
                return (today, usd, False)
            except ValueError:
                pass
    else:
        # $50.21 형태
        m = re.search(r'Near Mint[^$]{0,400}\$([\d,]+\.?\d*)', html, re.DOTALL)
        if m:
            try:
                usd = float(m.group(1).replace(",", ""))
                return (today, usd, False)
            except ValueError:
                pass
    return None


def parse_history(html, is_jp=False, jpy_krw=FALLBACK_JPY_KRW):
    """
    Returns:
        raw_nm:  [(date, price), ...]  ← JP는 JPY 원값, EN은 USD 원값
        psa10:   [(date, usd_price), ...]
        psa9:    [(date, usd_price), ...]
        raw_is_krw: raw_nm이 이미 KRW로 환산됐는지 여부
        raw_is_jpy: Prices 폴백 원값이 JPY였는지 여부
    """
    chart_pat = re.compile(
        r'new Chartkick\["LineChart"\]\("([^"]+)",\s*(\[.*?\]),\s*\{',
        re.DOTALL)

    raw_nm, psa10, psa9 = [], [], []

    for m in chart_pat.finditer(html):
        chart_id = m.group(1)
        data = m.group(2)

        if "_Raw_" in chart_id and not raw_nm:  # 첫 번째 _Raw_ 차트만 사용
            raw_nm = parse_raw_nm_series(data)
        elif "_PSA_" in chart_id:
            psa10 = parse_series_by_name(data, "PSA 10")
            psa9 = parse_series_by_name(data, "PSA 9")

    # 차트에서 RAW를 못 가져온 경우 → Prices 섹션 폴백
    raw_is_krw = False
    raw_is_jpy = False
    if not raw_nm:
        fallback = parse_prices_section_nm(html, is_jp)
        if fallback:
            date, value, is_jpy = fallback
            if is_jpy:
                krw = round(value * jpy_krw)
                raw_nm = [(date, krw)]
                raw_is_krw = True  # 이미 KRW로 환산됨
                raw_is_jpy = True
            else:
                raw_nm = [(date, value)]  # USD 그대로
                raw_is_jpy = False

    return raw_nm, psa10, psa9, raw_is_krw, raw_is_jpy


# ─── Sanity check ─────────────────────────────────────────────────────────────

HIGH_RARE_RARITIES = {"SR", "SAR", "SSR", "CSR", "CHR", "ACE", "UR", "HR", "MUR", "BWR"}
MIN_PRICE_HIGH_RARE = 0.3    # USD: 거의 0이면 파싱 오류, 정상 저가 카드는 통과
MAX_DAILY_CHANGE = 0.9       # 전일 대비 90% 이상 변화만 제거 (급등락 실제 반영)


def _save_anomaly(conn, card_id, source, reason, suspect_usd, hist_usd, ebay_result):
    """price_anomalies 테이블에 이상 이벤트 저장.
    PRICE_DROP_ACCEPTED: eBay에서 정상 하락 확인 → 감사 로그만 남기고 is_resolved=true 자동 처리.
    그 외(오염/미검증/오류): 관리자 검토 대기.
    """
    auto_resolve = (ebay_result == "PRICE_DROP_ACCEPTED")
    try:
        anomaly_id = "ANM_" + uuid.uuid4().hex[:16].upper()
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO price_anomalies
                    (anomaly_id, card_id, source, reason,
                     suspect_price_usd, hist_median_usd, ebay_result,
                     is_resolved, resolved_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
                """,
                (
                    anomaly_id, card_id, source, reason,
                    round(suspect_usd, 2) if suspect_usd else None,
                    round(hist_usd,   2) if hist_usd   else None,
                    ebay_result,
                    auto_resolve,
                    datetime.now() if auto_resolve else None,
                ),
            )
        conn.commit()
        tag = "(eBay 정상 확인, 자동 닫힘)" if auto_resolve else "(관리자 검토 필요)"
        safe_print(f"  [GUARD] 이상 기록 저장 → {anomaly_id} {tag}")
    except Exception as e:
        safe_print(f"  [GUARD] 이상 기록 저장 실패: {e}")
        try:
            conn.rollback()
        except Exception:
            pass


def _get_card_meta(conn, card_id) -> tuple:
    """eBay 검색용 카드 수록번호 조회. (name, collection_number) 반환."""
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT name, collection_number FROM cards WHERE card_id = %s",
                (card_id,),
            )
            row = cur.fetchone()
            return (row[0], row[1]) if row else (None, None)
    except Exception:
        return (None, None)


def _get_recent_grade_median(conn, card_id, source, grade_value, days=30, usd_krw=1400) -> Optional[float]:
    """최근 N일 PSA {grade_value} DB 가격의 중앙값 (USD 환산)."""
    try:
        since = (date.today() - timedelta(days=days)).isoformat()
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT price FROM price_snapshots
                WHERE card_id = %s AND source = %s
                  AND card_status = 'GRADED'
                  AND grading_company = 'PSA'
                  AND grade_value = %s
                  AND traded_at >= %s
                ORDER BY traded_at DESC
                LIMIT 30
                """,
                (card_id, source, grade_value, since),
            )
            rows = cur.fetchall()
        if not rows:
            return None
        prices_usd = [r[0] / usd_krw for r in rows]
        return statistics.median(prices_usd)
    except Exception:
        return None


def sanitize_raw(raw_nm, psa9, psa10, rarity):
    """RAW NM 시계열에서 이상값 제거. PSA10 > RAW > PSA9 순서 위반 시 제거."""
    is_high_rare = rarity in HIGH_RARE_RARITIES

    def last_avg(pts, n=5):
        vals = [p for _, p in pts[-n:] if p > 0]
        return sum(vals) / len(vals) if vals else None

    psa9_ref  = last_avg(psa9)
    psa10_ref = last_avg(psa10)

    # PSA10 > PSA9 위반 시 PSA 기준 자체를 신뢰할 수 없음 → 기준 무효화
    if psa10_ref and psa9_ref and psa10_ref < psa9_ref:
        safe_print(f"  [SANITY] PSA10 ${psa10_ref:.2f} < PSA9 ${psa9_ref:.2f} 순서 위반 → PSA 기준 무효화")
        psa10_ref = None
        psa9_ref = None

    clean = []
    prev_price = None
    for date, price in raw_nm:
        # RAW > PSA10 위반 (RAW가 PSA10보다 비싸면 이상)
        if psa10_ref and price > psa10_ref:
            safe_print(f"  [SANITY] {date} RAW ${price:.2f} > PSA10 ${psa10_ref:.2f} 순서 위반 → 제거")
            continue
        # RAW < PSA9 위반 허용 — PSA9 가격 아래면 경고만 (시장 이상이지 데이터 오류는 아님)
        if psa9_ref and price < psa9_ref * 0.5:
            safe_print(f"  [SANITY] {date} RAW ${price:.2f} < PSA9 ${psa9_ref:.2f}×0.5 비정상 저가 → 제거")
            continue
        # 고레어 최소가
        if is_high_rare and price < MIN_PRICE_HIGH_RARE:
            safe_print(f"  [SANITY] {date} RAW ${price:.2f} < 고레어 최소가 ${MIN_PRICE_HIGH_RARE} → 제거")
            continue
        # 전일 대비 급변
        if prev_price and prev_price > 0:
            ratio = abs(price - prev_price) / prev_price
            if ratio > MAX_DAILY_CHANGE:
                safe_print(f"  [SANITY] {date} RAW ${price:.2f} vs prev ${prev_price:.2f} 급변({ratio:.0%}) → 제거")
                continue
        clean.append((date, price))
        prev_price = price

    return clean


# ─── 저장 ─────────────────────────────────────────────────────────────────────

def save_history(conn, card_id, source, raw_nm, psa10, psa9, rarity,
                 since_date=None, usd_krw=FALLBACK_USD_KRW, raw_is_krw=False,
                 skip_sanitize=False, raw_rate=None, raw_is_jpy=False):
    """
    raw_nm: [(date, price), ...] — raw_is_krw=True면 이미 KRW, False면 raw_rate 적용
    psa10/psa9: [(date, usd_price), ...]
    skip_sanitize: 프로모 카드처럼 KO 시장 기준 sanity check가 의미없는 경우 True
    """
    # sanity check 적용 (raw_is_krw면 USD 기준 sanity 스킵, 프로모도 스킵)
    if not raw_is_krw and not skip_sanitize:
        raw_nm = sanitize_raw(raw_nm, psa9, psa10, rarity)

    existing_raw  = get_existing_dates(conn, card_id, source, "RAW")
    existing_p10  = get_existing_dates(conn, card_id, source, "GRADED", "10")
    existing_p9   = get_existing_dates(conn, card_id, source, "GRADED", "9")

    saved = 0
    with conn.cursor() as cur:
        for date, price in raw_nm:
            if since_date and date < since_date:
                continue
            if date in existing_raw:
                continue
            krw = price if raw_is_krw else round(price * (raw_rate or usd_krw))
            if raw_is_krw:
                r_price, r_currency = price, "KRW"
            elif source == "SCRYDEX_JP" and raw_is_jpy:
                r_price, r_currency = price, "JPY"
            else:
                r_price, r_currency = price, "USD"
            insert_snapshot(cur, card_id, source, krw, "RAW", date,
                            raw_price=r_price, raw_currency=r_currency)
            saved += 1

        # ── PSA10 이상 감지 가드 ──────────────────────────────────
        new_p10 = [
            (d, p) for d, p in psa10
            if (not since_date or d >= since_date) and d not in existing_p10
        ]
        if _EBAY_GUARD and len(new_p10) >= 2:
            new_p10_usd_vals = [p for _, p in new_p10]
            new_p10_avg = sum(new_p10_usd_vals) / len(new_p10_usd_vals)

            hist_med = _get_recent_grade_median(conn, card_id, source, "10",
                                                days=30, usd_krw=usd_krw)
            suspect = False
            reason = ""

            # 1) 기존 가격 대비 70% 이상 급락
            if hist_med and new_p10_avg < hist_med * 0.30:
                suspect = True
                reason = f"급락 ${new_p10_avg:,.0f} vs 기존중앙값 ${hist_med:,.0f} USD"

            # 2) PSA10 < PSA9 grade 역전 (엄격: PSA10이 PSA9보다 낮으면 무조건 의심)
            if not suspect:
                new_p9 = [
                    (d, p) for d, p in psa9
                    if (not since_date or d >= since_date) and d not in existing_p9
                ]
                if new_p9:
                    new_p9_avg = sum(p for _, p in new_p9) / len(new_p9)
                    if new_p10_avg < new_p9_avg:
                        suspect = True
                        reason = f"등급역전 PSA10avg=${new_p10_avg:,.0f} < PSA9avg=${new_p9_avg:,.0f} USD"

            # 3) PSA10 < RAW (RAW가 더 비싸면 PSA10 데이터 의심)
            # raw_is_krw=True인 경우 raw_nm이 KRW이므로 USD로 환산 후 비교
            if not suspect and raw_nm and not raw_is_krw:
                raw_ref = sum(p for _, p in raw_nm[-5:] if p > 0) / max(len([p for _, p in raw_nm[-5:] if p > 0]), 1)
                if raw_ref > 0 and new_p10_avg < raw_ref * 0.9:
                    suspect = True
                    reason = f"RAW>${raw_ref:,.0f} > PSA10avg=${new_p10_avg:,.0f} 순서 위반"

            if suspect:
                safe_print(f"  [GUARD] {card_id} {source} 이상 감지 → {reason}")
                ebay_result = "SKIPPED"
                try:
                    _, col_num = _get_card_meta(conn, card_id)
                    if col_num:
                        is_valid = price_ebay.validate_price(col_num, "10", new_p10_avg, hist_med)
                        if not is_valid:
                            safe_print(f"  [GUARD] eBay 교차검증 실패 → PSA10 저장 스킵")
                            psa10 = []   # 이번 배치 PSA10 저장 전체 스킵
                            ebay_result = "CONTAMINATION_CONFIRMED"
                        else:
                            ebay_result = "PRICE_DROP_ACCEPTED"
                    else:
                        ebay_result = "NO_COL_NUM"
                except Exception as e:
                    safe_print(f"  [GUARD] eBay 검증 오류 ({e}) → 보수적 수용")
                    ebay_result = "EBAY_ERROR"
                # 어드민 웹 알림용 DB 저장
                _save_anomaly(conn, card_id, source, reason, new_p10_avg, hist_med, ebay_result)
        # ─────────────────────────────────────────────────────────

        for date, usd in psa10:
            if since_date and date < since_date:
                continue
            if date in existing_p10:
                continue
            insert_snapshot(cur, card_id, source,
                            round(usd * usd_krw), "GRADED", date,
                            grading_company="PSA", grade_value="10")
            saved += 1

        for date, usd in psa9:
            if since_date and date < since_date:
                continue
            if date in existing_p9:
                continue
            insert_snapshot(cur, card_id, source,
                            round(usd * usd_krw), "GRADED", date,
                            grading_company="PSA", grade_value="9")
            saved += 1

    conn.commit()
    return saved


# ─── 메인 ────────────────────────────────────────────────────────────────────

def process_card(card_id, en_ref, jp_ref, rarity, since_date, idx, total, usd_krw, jpy_krw, is_promo_exclusive=False):
    """각 카드를 독립 DB 연결로 처리 (스레드 안전)"""
    conn = get_conn()
    total_saved = 0
    try:
        log_lines = []
        for ref, source, is_jp in [
            (en_ref, "SCRYDEX_EN", False),
            (jp_ref, "SCRYDEX_JP", True),
        ]:
            if not ref or ref.startswith("NO_"):
                continue

            html = fetch_html(ref)
            if not html:
                continue

            raw_nm, psa10, psa9, raw_is_krw, raw_is_jpy = parse_history(html, is_jp=is_jp, jpy_krw=jpy_krw)

            raw_cnt = len([d for d, _ in raw_nm if not since_date or d >= since_date])
            p10_cnt = len([d for d, _ in psa10 if not since_date or d >= since_date])
            p9_cnt  = len([d for d, _ in psa9  if not since_date or d >= since_date])
            tag = " [Prices폴백]" if raw_is_krw else ""
            log_lines.append(f"    {source}: RAW={raw_cnt}일{tag} PSA10={p10_cnt}일 PSA9={p9_cnt}일")

            raw_rate = jpy_krw if (is_jp and raw_is_jpy) else usd_krw
            saved = save_history(conn, card_id, source, raw_nm, psa10, psa9,
                                 rarity or "", since_date, usd_krw, raw_is_krw,
                                 skip_sanitize=is_promo_exclusive or is_jp,
                                 raw_rate=raw_rate, raw_is_jpy=raw_is_jpy)
            total_saved += saved
            time.sleep(SLEEP)

        msg = f"[{idx}/{total}] {card_id}"
        if log_lines:
            msg += "\n" + "\n".join(log_lines)
        if total_saved > 0:
            msg += f"\n    → 저장: {total_saved}건"
        safe_print(msg)

    except Exception as e:
        safe_print(f"[{idx}/{total}] {card_id} [ERROR] {e}")
    finally:
        conn.close()

    return total_saved


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--backfill", action="store_true",
                        help="전체 히스토리 백필 (첫 실행용)")
    parser.add_argument("--card-id", help="특정 카드 ID만 처리")
    parser.add_argument("--days", type=int, default=3,
                        help="일별 동기화 시 가져올 최근 N일 (기본: 3)")
    parser.add_argument("--workers", type=int, default=8,
                        help="병렬 스레드 수 (기본: 8)")
    args = parser.parse_args()

    since_date = None if args.backfill else \
        (datetime.now() - timedelta(days=args.days)).strftime("%Y-%m-%d")

    usd_krw, jpy_krw = fetch_exchange_rates()
    print(f"환율: 1 USD = {usd_krw:.0f} KRW, 1 JPY = {jpy_krw:.2f} KRW", flush=True)

    if args.backfill:
        print(f"=== scrydex 전체 히스토리 백필 (workers={args.workers}) ===", flush=True)
    else:
        print(f"=== scrydex 일별 동기화 (since {since_date}, workers={args.workers}) ===", flush=True)

    conn = get_conn()
    cards = get_mapped_cards(conn)
    conn.close()

    if args.card_id:
        cards = [c for c in cards if c[0] == args.card_id]

    total = len(cards)
    print(f"대상 카드: {total}장\n", flush=True)
    total_saved = 0

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(process_card, card_id, en_ref, jp_ref, rarity,
                            since_date, i, total, usd_krw, jpy_krw,
                            is_promo_exclusive=bool(is_promo)): card_id
            for i, (card_id, en_ref, jp_ref, rarity, is_promo) in enumerate(cards, 1)
        }
        for future in as_completed(futures):
            try:
                total_saved += future.result()
            except Exception as e:
                safe_print(f"[ERROR] {futures[future]}: {e}")

    print(f"\n=== 완료: 총 {total_saved}건 저장 ===", flush=True)


def refresh_ko_estimates_best_effort():
    """scrydex 동기화 후 백엔드 KO_ESTIMATED 재계산을 best-effort로 호출한다."""
    try:
        resp = requests.post(KO_ESTIMATE_REFRESH_URL, timeout=60)
        if 200 <= resp.status_code < 300:
            safe_print(f"[KO_ESTIMATED] 재계산 API 호출 성공: HTTP {resp.status_code}")
        else:
            safe_print(f"[KO_ESTIMATED] 재계산 API 호출 실패: HTTP {resp.status_code} {resp.text[:300]}")
    except Exception as e:
        safe_print(f"[KO_ESTIMATED] 재계산 API 호출 실패(무시): {e}")


if __name__ == "__main__":
    main()
    # Hotfix-B (Codex CRITICAL #2): scrydex 종료 직후 KO refresh 호출 제거.
    # 23:00 Python recalc_coefficients가 계수 갱신 전이라 옛 계수로 잘못 계산 위험.
    # KO_ESTIMATED 최종 갱신은 23:45 Java refreshKoEstimatesFromSnapshots() 단독 책임.
