#!/usr/bin/env python3
"""
recalc_coefficients.py — NAVER_CAFE 낙찰가 기반 레어도별 JP/EN 분리 계수 재계산

NAVER 낙찰가 / SCRYDEX_JP → ko_coef_jp_{rarity}
NAVER 낙찰가 / SCRYDEX_EN → ko_coef_en_{rarity}
JP median > 1.0 또는 샘플 부족 → JP 계수 저장 안 함

사용:
  python3 /tmp/recalc_coefficients.py            # 계산 + 적용
  python3 /tmp/recalc_coefficients.py --dry-run  # 계산만 확인
"""

import argparse
import statistics
import uuid
import logging
from datetime import datetime

import psycopg2
import requests

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
log = logging.getLogger(__name__)

DB_DSN = 'host=localhost port=5432 dbname=pokemon_card_db user=nightfury'
# 외부 API 호출은 price_scrydex.py 또는 Java ExchangeRateClient가 처음 호출하면서 DB에 저장.
# recalc_coefficients.py는 DB 조회만 — 단일 환율 보장(REFACTOR_2026-05-12.md 2-①).
EXCHANGE_API_FALLBACK = 'https://open.er-api.com/v6/latest/USD'
MIN_SAMPLES = 10         # 최소 샘플 수 (10 미만은 신뢰도 부족)
DAYS = 60                # 최근 N일 낙찰가만 사용
IQR_FENCE = 1.5          # IQR 이상치 제거 배수
MAX_COEF = 1.0           # JP 계수 상한 (초과 시 invalid 처리)
RATIO_FLOOR = 0.05       # 산출 시점 ratio guard 하한 (입력 단위 오류/오입력 방어)
RATIO_CEILING = 3.0      # 산출 시점 ratio guard 상한 (분포 p99=3.58 기준 조정 가능)
KO_MARKET_ADJUSTMENT = 1.12  # 기본값 (DB에 ko_adjustment_factor 없을 때 fallback)

# 수동 보정값 유지 (자동 계산 대상 제외)
EXCLUDE_RARITIES = {'PR', 'HR', 'SSR', 'MA', 'S'}

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
}


def get_exchange_rates(conn=None) -> dict:
    """우선순위: DB 오늘자(SYSTEM) → 외부 API + DB 저장 → fallback(메모리만).
    외부 API 실패 시 fallback은 DB에 박지 않음 — Hotfix-A (Codex CRITICAL #3).
    """
    close_after = False
    if conn is None:
        conn = psycopg2.connect(DB_DSN)
        close_after = True
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT card_id, price FROM price_snapshots
                WHERE card_id IN ('exchange_rate_usd', 'exchange_rate_jpy')
                  AND source = 'SYSTEM' AND DATE(traded_at) = CURRENT_DATE
                ORDER BY traded_at DESC
            """)
            rates = {r[0]: r[1] / 100.0 for r in cur.fetchall()}
        if 'exchange_rate_usd' in rates and 'exchange_rate_jpy' in rates:
            return {'USD': rates['exchange_rate_usd'], 'JPY': rates['exchange_rate_jpy']}

        usd_krw, jpy_krw = 1380.0, 9.2
        api_ok = False
        try:
            r = requests.get(EXCHANGE_API_FALLBACK, timeout=10, headers=HEADERS)
            rates_api = r.json()['rates']
            usd_krw = float(rates_api['KRW'])
            jpy_krw = usd_krw / float(rates_api['JPY'])
            api_ok = True
        except Exception as e:
            log.warning(f'환율 외부 조회 실패: {e} → fallback USD=1380, JPY=9.2 (DB 저장 안 함)')

        if api_ok:
            # Hotfix-D (Codex CRITICAL #4): Java/Python 동시 INSERT 시 unique violation 무시
            for card_id, value in [('exchange_rate_usd', usd_krw), ('exchange_rate_jpy', jpy_krw)]:
                try:
                    with conn.cursor() as cur:
                        cur.execute("""
                            SELECT 1 FROM price_snapshots
                            WHERE card_id=%s AND source='SYSTEM' AND DATE(traded_at)=CURRENT_DATE LIMIT 1
                        """, (card_id,))
                        if cur.fetchone():
                            continue
                        cur.execute("""
                            INSERT INTO price_snapshots
                              (price_snapshot_id, card_id, source, price, card_status, traded_at, collected_at)
                            VALUES (%s, %s, 'SYSTEM', %s, 'RAW', NOW(), NOW())
                        """, (uuid.uuid4().hex[:32], card_id, int(round(value * 100))))
                    conn.commit()
                except psycopg2.errors.UniqueViolation:
                    conn.rollback()
                    log.info(f'[ExchangeRate] {card_id} 동시 저장 race — 다른 프로세스가 박음, 무시')
                except Exception:
                    conn.rollback()
                    raise
        return {'USD': usd_krw, 'JPY': jpy_krw}
    finally:
        if close_after:
            conn.close()


def _calc_coefficients(conn, exchange_rates: dict, scrydex_source: str) -> dict:
    """지정된 SCRYDEX 소스 기준으로 레어도별 계수 계산"""
    usd = exchange_rates['USD']
    jpy = exchange_rates['JPY']
    with conn.cursor() as cur:
        cur.execute(f"""
            WITH raw AS (
              SELECT
                c.rarity_code,
                nc.price::float / NULLIF(
                  s.raw_price * CASE s.raw_currency
                    WHEN 'USD' THEN %s
                    WHEN 'JPY' THEN %s
                  END,
                  0
                ) AS ratio
              FROM price_snapshots nc
              JOIN cards c ON c.card_id = nc.card_id
              JOIN (
                SELECT DISTINCT ON (card_id) card_id, raw_price, raw_currency
                FROM price_snapshots
                WHERE source = '{scrydex_source}'
                  AND card_status = 'RAW'
                  AND raw_price IS NOT NULL
                  AND raw_currency IN ('USD', 'JPY')
                ORDER BY card_id, traded_at DESC
              ) s ON s.card_id = nc.card_id
              WHERE nc.source IN ('NAVER_CAFE', 'NAVER_CAFE_OLD', 'DAANGN')
                AND nc.validation_status = 'VALID'
                AND nc.card_status = 'RAW'
                AND nc.traded_at > NOW() - INTERVAL '{DAYS} days'
                AND nc.price > 5000
                AND s.raw_price * CASE s.raw_currency
                    WHEN 'USD' THEN %s
                    WHEN 'JPY' THEN %s
                  END > 5000
                AND c.rarity_code IS NOT NULL
            ),
            filtered AS (
              -- 산출 시점 ratio guard: 입력 단위 오류/명백한 오입력 차단
              -- (예: SR 14,000원 → ratio 0.037, 스탬프박스 PR ratio 0.009 등)
              SELECT * FROM raw
              WHERE ratio BETWEEN {RATIO_FLOOR} AND {RATIO_CEILING}
            ),
            iqr AS (
              SELECT
                rarity_code,
                PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY ratio) AS q1,
                PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY ratio) AS q3
              FROM filtered GROUP BY rarity_code
            )
            SELECT
              r.rarity_code,
              COUNT(*) AS samples,
              PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.ratio) AS median_coef
            FROM filtered r
            JOIN iqr i ON i.rarity_code = r.rarity_code
            WHERE r.ratio BETWEEN i.q1 - {IQR_FENCE} * (i.q3 - i.q1)
                               AND i.q3 + {IQR_FENCE} * (i.q3 - i.q1)
            GROUP BY r.rarity_code
            HAVING COUNT(*) >= {MIN_SAMPLES}
            ORDER BY COUNT(*) DESC
        """, (usd, jpy, usd, jpy))
        rows = cur.fetchall()

    return {row[0]: {'samples': row[1], 'coef': round(row[2], 4)} for row in rows}


def calculate_jp_coefficients(conn, exchange_rates: dict) -> dict:
    return _calc_coefficients(conn, exchange_rates, 'SCRYDEX_JP')


def calculate_en_coefficients(conn, exchange_rates: dict) -> dict:
    return _calc_coefficients(conn, exchange_rates, 'SCRYDEX_EN')


def get_market_adjustment(conn) -> float:
    with conn.cursor() as cur:
        cur.execute("""
            SELECT price FROM price_snapshots
            WHERE card_id = 'ko_adjustment_factor' AND source = 'SYSTEM'
            ORDER BY traded_at DESC LIMIT 1
        """)
        row = cur.fetchone()
        return (row[0] / 10000.0) if row else KO_MARKET_ADJUSTMENT


def get_global_coefficient(conn) -> float:
    with conn.cursor() as cur:
        cur.execute("""
            SELECT price FROM price_snapshots
            WHERE card_id = 'ko_market_coefficient' AND source = 'SYSTEM'
            ORDER BY traded_at DESC LIMIT 1
        """)
        row = cur.fetchone()
        return (row[0] / 10000.0) if row else 0.777


_INSERT_SQL = """
    INSERT INTO price_snapshots
      (price_snapshot_id, card_id, source, price, card_status, traded_at, collected_at)
    VALUES (%s, %s, 'SYSTEM', %s, 'RAW', %s, %s)
"""


def _filter_valid(jp_coeffs: dict, en_coeffs: dict) -> tuple:
    """EXCLUDE_RARITIES + MAX_COEF 가드 통과한 valid coef 분리. 제외 사유는 log만."""
    jp_valid, en_valid = {}, {}
    for rarity, info in jp_coeffs.items():
        if rarity in EXCLUDE_RARITIES:
            log.info(f'  [JP] 제외 (EXCLUDE_RARITIES): {rarity}')
            continue
        if info['coef'] > MAX_COEF:
            log.info(f'  [JP] 제외 (median {info["coef"]:.4f} > {MAX_COEF}): {rarity}')
            continue
        jp_valid[rarity] = info
    for rarity, info in en_coeffs.items():
        if rarity in EXCLUDE_RARITIES:
            log.info(f'  [EN] 제외 (EXCLUDE_RARITIES): {rarity}')
            continue
        en_valid[rarity] = info
    return jp_valid, en_valid


def save_rarity_coefficients(conn, jp_valid: dict, en_valid: dict, now: datetime):
    """RARITY-specific (ko_coef_jp_SR/SAR 등) + fallback (ko_coef_SR) 저장.
    GLOBAL은 save_global_coefficients가 처리 — 이중 저장 금지.
    월요일 03:00 cron (--mode rarity)에서 호출 예정.
    """
    rows = []

    for rarity, info in jp_valid.items():
        card_id = f'ko_coef_jp_{rarity}'
        adjusted = round(info['coef'] * KO_MARKET_ADJUSTMENT, 4)
        rows.append((uuid.uuid4().hex, card_id, int(adjusted * 10000), now, now))
        log.info(f'  [JP] {card_id} = {info["coef"]} × {KO_MARKET_ADJUSTMENT} = {adjusted} ({info["samples"]}샘플)')

    for rarity, info in en_valid.items():
        card_id = f'ko_coef_en_{rarity}'
        adjusted = round(info['coef'] * KO_MARKET_ADJUSTMENT, 4)
        rows.append((uuid.uuid4().hex, card_id, int(adjusted * 10000), now, now))
        log.info(f'  [EN] {card_id} = {info["coef"]} × {KO_MARKET_ADJUSTMENT} = {adjusted} ({info["samples"]}샘플)')

    # ko_coef_{rarity}: JP 유효 → JP값, 아니면 EN값 (fallback)
    all_rarities = set(jp_valid) | set(en_valid)
    for rarity in all_rarities:
        if rarity in jp_valid:
            coef = jp_valid[rarity]['coef']
            src = 'JP'
        else:
            coef = en_valid[rarity]['coef']
            src = 'EN'
        card_id = f'ko_coef_{rarity}'
        adjusted = round(coef * KO_MARKET_ADJUSTMENT, 4)
        rows.append((uuid.uuid4().hex, card_id, int(adjusted * 10000), now, now))
        log.info(f'  [FALLBACK/{src}] {card_id} = {coef} × {KO_MARKET_ADJUSTMENT} = {adjusted}')

    if rows:
        with conn.cursor() as cur:
            cur.executemany(_INSERT_SQL, rows)
        conn.commit()


def save_global_coefficients(conn, jp_valid: dict, en_valid: dict, now: datetime):
    """GLOBAL: raw 가중평균 → _GLOBAL_RAW 적층 → 최근 7obs median → 기존 _GLOBAL 키.

    매일 23:00 cron (--mode global)에서 호출 예정.
    - ko_coef_jp_GLOBAL_RAW / ko_coef_en_GLOBAL_RAW: substrate, Java 무관 (LIKE 'ko_coef_%' 매칭되지만 lookup miss로 무해)
    - ko_coef_jp_GLOBAL / ko_coef_en_GLOBAL: 기존 키, Java가 읽음. 값=7obs median.
    - median 기준: ORDER BY traded_at DESC LIMIT 7 (calendar days X, observation 7개)
    - observation 7개 미만 시 가진 만큼으로 median (초기 운영 자연 처리)
    """
    # Step 1+2: raw global 계산 + _RAW INSERT
    raw_rows = []
    raw_values = {}  # {'jp': 0.3932, 'en': 0.3663}

    for src_key, valid_dict in [('jp', jp_valid), ('en', en_valid)]:
        if not valid_dict:
            log.warning(f'  [{src_key.upper()}_GLOBAL] valid coef 없음, 스킵')
            continue
        total_samples = sum(v['samples'] for v in valid_dict.values())
        weighted = sum(v['coef'] * v['samples'] for v in valid_dict.values())
        raw = round((weighted / total_samples) * KO_MARKET_ADJUSTMENT, 4)
        raw_values[src_key] = raw
        raw_key = f'ko_coef_{src_key}_GLOBAL_RAW'
        raw_rows.append((uuid.uuid4().hex, raw_key, int(raw * 10000), now, now))
        log.info(f'  [{src_key.upper()}_GLOBAL_RAW] = {raw} (samples={total_samples})')

    if raw_rows:
        with conn.cursor() as cur:
            cur.executemany(_INSERT_SQL, raw_rows)
        conn.commit()

    # Step 3+4: 7obs median → 기존 GLOBAL 키 INSERT
    smooth_rows = []
    for src_key in raw_values:
        raw_key = f'ko_coef_{src_key}_GLOBAL_RAW'
        smooth_key = f'ko_coef_{src_key}_GLOBAL'

        with conn.cursor() as cur:
            cur.execute("""
                SELECT price/10000.0 FROM price_snapshots
                WHERE card_id = %s AND source = 'SYSTEM'
                ORDER BY traded_at DESC LIMIT 7
            """, (raw_key,))
            observations = [float(r[0]) for r in cur.fetchall()]

        if not observations:
            log.warning(f'  [{smooth_key}] _RAW substrate 없음 — backfill 필요, 스킵')
            continue

        median = round(statistics.median(observations), 4)
        smooth_rows.append((uuid.uuid4().hex, smooth_key, int(median * 10000), now, now))
        obs_str = ', '.join(f'{o:.4f}' for o in observations)
        log.info(f'  [{smooth_key}] 7obs window: [{obs_str}] → median = {median}')

    if smooth_rows:
        with conn.cursor() as cur:
            cur.executemany(_INSERT_SQL, smooth_rows)
        conn.commit()


def save_all_coefficients(conn, jp_coeffs: dict, en_coeffs: dict, now: datetime,
                          market_adj: float = KO_MARKET_ADJUSTMENT, mode: str = 'both'):
    """Mode 분기 wrapper.

    - mode='global': GLOBAL만 (매일 cron)
    - mode='rarity': RARITY만 (월요일 cron)
    - mode='both': 둘 다 (수동 트리거 / 기존 동작 호환 default)

    EXCLUDE_RARITIES + MAX_COEF 가드는 _filter_valid로 한 번만 처리.
    """
    jp_valid, en_valid = _filter_valid(jp_coeffs, en_coeffs)

    if mode in ('rarity', 'both'):
        save_rarity_coefficients(conn, jp_valid, en_valid, now)
    if mode in ('global', 'both'):
        save_global_coefficients(conn, jp_valid, en_valid, now)


def popularity_multiplier(score) -> float:
    score = score or 0
    if score >= 45:
        return 1.25
    if score >= 30:
        return 1.15
    if score >= 15:
        return 1.05
    return 1.0




def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true', help='계산 결과만 출력, DB 미저장')
    parser.add_argument('--mode', choices=['global', 'rarity', 'both'], default='both',
                        help='global: GLOBAL만 (매일 23:00 cron) / rarity: RARITY만 (월요일 03:00 cron) / both: 둘 다 (수동 트리거, default)')
    args = parser.parse_args()

    conn = psycopg2.connect(DB_DSN)
    exchange_rates = get_exchange_rates(conn)  # Hotfix-C: 기존 conn 재사용 (별도 conn 생성 방지)
    log.info(f'환율 USD={exchange_rates["USD"]:.0f} JPY={exchange_rates["JPY"]:.2f}')

    global_coef = get_global_coefficient(conn)
    log.info(f'글로벌 계수: {global_coef}')

    market_adj = get_market_adjustment(conn)
    log.info(f'시장 보정 계수: {market_adj} (DB 값, 기본값={KO_MARKET_ADJUSTMENT})')

    log.info('\nJP 계수 계산 중...')
    jp_coeffs = calculate_jp_coefficients(conn, exchange_rates)

    log.info('\nEN 계수 계산 중...')
    en_coeffs = calculate_en_coefficients(conn, exchange_rates)

    if not jp_coeffs and not en_coeffs:
        log.warning('계산 가능한 계수 없음 (샘플 부족)')
        conn.close()
        return

    log.info('\n=== JP 기준 계수 ===')
    for rarity, info in jp_coeffs.items():
        valid = info['coef'] <= MAX_COEF and rarity not in EXCLUDE_RARITIES
        log.info(f'  {rarity:6s}: {info["coef"]:.4f}  ({info["samples"]}샘플) {"✓" if valid else "✗ invalid"}')

    log.info('\n=== EN 기준 계수 ===')
    for rarity, info in en_coeffs.items():
        valid = rarity not in EXCLUDE_RARITIES
        log.info(f'  {rarity:6s}: {info["coef"]:.4f}  ({info["samples"]}샘플) {"✓" if valid else "✗ exclude"}')

    if args.dry_run:
        log.info('\n[dry-run] DB 저장 생략')
        conn.close()
        return

    now = datetime.now()
    log.info(f'\n계수 DB 저장 중... (mode={args.mode})')
    save_all_coefficients(conn, jp_coeffs, en_coeffs, now, market_adj, mode=args.mode)

    # KO_ESTIMATED 재생성은 Java 스케줄러(14:00 refreshKoEstimates)가 처리한다.
    # selectScrydexSnapshotForKo / suspect / spread 로직을 통과해야 하므로 Python에서 직접 쓰지 않음.
    conn.close()
    log.info('완료 (KO_ESTIMATED는 Java 스케줄러가 재계산)')


if __name__ == '__main__':
    main()
