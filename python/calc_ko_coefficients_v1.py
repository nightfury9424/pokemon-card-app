#!/usr/bin/env python3
"""Phase 1 bootstrap: KO_ESTIMATED 계수 1회 산출.

CARD coef: IQR filter 후 n >= 5만 저장 (BLEND/JP/EN 셋 다)
RARITY coef: 시간 가중 7:3 + IQR + weighted median (BLEND/JP/EN 셋 다)
data_source: BOOTSTRAP_NAVER_DAANGN
batch_id: BOOTSTRAP_YYYYMMDD_V1

사용:
  python3 /tmp/calc_ko_coefficients_v1.py           # dry-run
  python3 /tmp/calc_ko_coefficients_v1.py --apply   # DB INSERT
"""
from __future__ import annotations
import argparse
import logging
import statistics
from datetime import datetime, timedelta

import psycopg2

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
log = logging.getLogger(__name__)

DB = {'dbname': 'pokemon_card_db', 'user': 'nightfury'}
DAYS = 60
IQR_FENCE = 1.5
MIN_SAMPLES_CARD = 5     # CARD coef n>=5
MIN_SAMPLES_RARITY = 10  # RARITY coef n>=10
PRICE_FLOOR = 5000
MAX_COEF = 1.0           # 옵션 B — CHR/S 등 한국 시장 ↑ 카드도 1.0 cap (보수적)


def get_rates(cur) -> tuple[float, float]:
    cur.execute("""
        SELECT card_id, price FROM price_snapshots
        WHERE card_id IN ('exchange_rate_usd','exchange_rate_jpy') AND source='SYSTEM'
          AND DATE(traded_at)=CURRENT_DATE
        ORDER BY traded_at DESC
    """)
    rates = {r[0]: r[1]/100.0 for r in cur.fetchall()}
    usd = rates.get('exchange_rate_usd', 1492.0)
    jpy = rates.get('exchange_rate_jpy', 9.43)
    return usd, jpy


def fetch_with_scrydex(cur, usd: float, jpy: float):
    """v_ko_actual_prices + 시점 매칭 SCRYDEX JP/EN raw_price."""
    cur.execute("""
        WITH actual AS (
            SELECT card_id, price, traded_at, card_status, source
            FROM v_ko_actual_prices
            WHERE traded_at > NOW() - INTERVAL %s
        )
        SELECT
            a.card_id, c.rarity_code, a.price, a.traded_at, a.source,
            jp.raw_price AS jp_raw, jp.raw_currency AS jp_cur,
            en.raw_price AS en_raw
        FROM actual a
        JOIN cards c ON c.card_id = a.card_id
        LEFT JOIN LATERAL (
            SELECT raw_price, raw_currency FROM price_snapshots
            WHERE source='SCRYDEX_JP' AND card_id=a.card_id AND card_status='RAW'
              AND raw_price IS NOT NULL AND raw_currency IN ('USD','JPY')
            ORDER BY ABS(EXTRACT(EPOCH FROM (traded_at - a.traded_at))) LIMIT 1
        ) jp ON true
        LEFT JOIN LATERAL (
            SELECT raw_price FROM price_snapshots
            WHERE source='SCRYDEX_EN' AND card_id=a.card_id AND card_status='RAW'
              AND raw_price IS NOT NULL AND raw_currency='USD'
            ORDER BY ABS(EXTRACT(EPOCH FROM (traded_at - a.traded_at))) LIMIT 1
        ) en ON true
        WHERE c.rarity_code IS NOT NULL
    """, (f'{DAYS} days',))
    rows = cur.fetchall()

    out = []
    for cid, rar, price, traded, src, jp_raw, jp_cur, en_raw in rows:
        if price < PRICE_FLOOR:
            continue
        jp_krw = None
        if jp_raw is not None:
            mult = usd if jp_cur == 'USD' else (jpy if jp_cur == 'JPY' else None)
            if mult:
                jp_krw = float(jp_raw) * mult
                if jp_krw < PRICE_FLOOR: jp_krw = None
        en_krw = None
        if en_raw is not None:
            en_krw = float(en_raw) * usd
            if en_krw < PRICE_FLOOR: en_krw = None
        out.append({
            'card_id': cid, 'rarity': rar, 'price': float(price),
            'traded_at': traded, 'source': src,
            'jp_krw': jp_krw, 'en_krw': en_krw,
        })
    return out


def iqr_fence(values: list[float], fence: float = IQR_FENCE) -> list[float]:
    if len(values) < 4: return values
    sv = sorted(values)
    n = len(sv)
    q1 = sv[n//4]
    q3 = sv[3*n//4]
    iqr = q3 - q1
    lo, hi = q1 - fence*iqr, q3 + fence*iqr
    return [v for v in values if lo <= v <= hi]


def iqr_over_median(values: list[float]) -> float:
    if len(values) < 2: return 0.0
    sv = sorted(values)
    n = len(sv)
    q1 = sv[n//4]
    q3 = sv[3*n//4]
    med = statistics.median(sv)
    return (q3 - q1) / med if med > 0 else 0.0


def time_weight(traded_at: datetime, now: datetime) -> int:
    delta = (now - traded_at).days
    if delta <= 14: return 7
    if delta <= DAYS: return 3
    return 0


def weighted_median(values_weights: list[tuple[float, int]]) -> float:
    """Weighted median via row expansion."""
    if not values_weights: return 0.0
    expanded = []
    for v, w in values_weights:
        expanded.extend([v] * w)
    if not expanded: return 0.0
    return statistics.median(expanded)


def calc_card_coefs(data: list[dict]) -> dict:
    """카드별 BLEND/JP/EN coef (n >= MIN_SAMPLES_CARD)."""
    by_card = {}
    for d in data:
        by_card.setdefault(d['card_id'], []).append(d)

    results = {}
    for cid, items in by_card.items():
        ratios_blend, ratios_jp, ratios_en = [], [], []
        for d in items:
            if d['jp_krw'] and d['en_krw']:
                ratios_blend.append(d['price'] / ((d['jp_krw'] + d['en_krw']) / 2))
            if d['jp_krw']:
                ratios_jp.append(d['price'] / d['jp_krw'])
            if d['en_krw']:
                ratios_en.append(d['price'] / d['en_krw'])

        coefs = {}
        for ctype, ratios in [('BLEND', ratios_blend), ('JP', ratios_jp), ('EN', ratios_en)]:
            filtered = iqr_fence(ratios)
            if len(filtered) >= MIN_SAMPLES_CARD:
                med = statistics.median(filtered)
                capped = min(med, MAX_COEF)        # 옵션 B cap (카드별도 동일 적용)
                coefs[ctype] = {
                    'coef': capped,
                    'coef_raw': med,
                    'capped': capped < med,
                    'n': len(filtered),
                    'iqr_over_median': iqr_over_median(filtered),
                    'rarity': items[0]['rarity'],
                }
        if coefs:
            results[cid] = coefs
    return results


def calc_rarity_coefs(data: list[dict], now: datetime) -> dict:
    """레어도별 BLEND/JP/EN coef (시간 가중 7:3, IQR unweighted)."""
    by_rarity = {}
    for d in data:
        by_rarity.setdefault(d['rarity'], []).append(d)

    results = {}
    for rar, items in by_rarity.items():
        ratios_blend, ratios_jp, ratios_en = [], [], []
        for d in items:
            w = time_weight(d['traded_at'], now)
            if w == 0: continue
            if d['jp_krw'] and d['en_krw']:
                ratios_blend.append((d['price'] / ((d['jp_krw'] + d['en_krw']) / 2), w))
            if d['jp_krw']:
                ratios_jp.append((d['price'] / d['jp_krw'], w))
            if d['en_krw']:
                ratios_en.append((d['price'] / d['en_krw'], w))

        coefs = {}
        for ctype, vw_list in [('BLEND', ratios_blend), ('JP', ratios_jp), ('EN', ratios_en)]:
            if not vw_list: continue
            raw_values = [v for v, w in vw_list]
            filtered_raw = set(map(id, iqr_fence(raw_values)))
            # IQR pass된 값들 — re-pair with weights
            filt_vw = []
            seen = []
            for v, w in vw_list:
                # iqr_fence는 same values 중복 가능. 단순 비교
                pass
            # 단순 구현: IQR fence 결과를 set으로
            filt_set = iqr_fence(raw_values)
            from collections import Counter
            filt_counter = Counter(filt_set)
            for v, w in vw_list:
                if filt_counter[v] > 0:
                    filt_vw.append((v, w))
                    filt_counter[v] -= 1

            if len(filt_vw) >= MIN_SAMPLES_RARITY:
                med = weighted_median(filt_vw)
                capped = min(med, MAX_COEF)        # 옵션 B cap
                coefs[ctype] = {
                    'coef': capped,
                    'coef_raw': med,                # audit용 원본 median
                    'capped': capped < med,
                    'n_raw': len(vw_list),
                    'n_filtered': len(filt_vw),
                    'iqr_over_median': iqr_over_median(filt_set),
                }
        if coefs:
            results[rar] = coefs
    return results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apply', action='store_true', help='DB INSERT')
    args = parser.parse_args()

    now = datetime.now()
    batch_id = f"BOOTSTRAP_{now.strftime('%Y%m%d')}_V1"
    expires_at = now + timedelta(days=180)
    data_source = "BOOTSTRAP_NAVER_DAANGN"

    conn = psycopg2.connect(**DB)
    cur = conn.cursor()

    usd, jpy = get_rates(cur)
    log.info(f"Exchange rates: USD={usd:.0f} JPY={jpy:.2f}")
    log.info(f"Batch ID: {batch_id}, expires_at: {expires_at.date()}")

    data = fetch_with_scrydex(cur, usd, jpy)
    log.info(f"Verified trades fetched: {len(data)}")

    # --- CARD coefs ---
    log.info("\n=== CARD coefficients (n >= 5) ===")
    card_coefs = calc_card_coefs(data)
    log.info(f"CARD coef cards: {len(card_coefs)}")

    # Get card names
    cur.execute("SELECT card_id, name, rarity_code FROM cards WHERE card_id = ANY(%s)",
                (list(card_coefs.keys()),))
    name_map = {r[0]: (r[1], r[2]) for r in cur.fetchall()}

    for cid, coefs in sorted(card_coefs.items(), key=lambda x: -max(c['n'] for c in x[1].values())):
        name, rar = name_map.get(cid, ('?', '?'))
        log.info(f"  {cid[:16]}... {rar:4s} {name[:30]:30s}")
        for ctype, info in coefs.items():
            log.info(f"      {ctype:5s}: coef={info['coef']:.4f}  n={info['n']}  iqr/med={info['iqr_over_median']:.3f}")

    # --- RARITY coefs ---
    log.info("\n=== RARITY coefficients (시간 가중 7:3, n_filtered >= 10) ===")
    rarity_coefs = calc_rarity_coefs(data, now)
    for rar in sorted(rarity_coefs.keys(), key=lambda r: -max(c.get('n_filtered',0) for c in rarity_coefs[r].values())):
        coefs = rarity_coefs[rar]
        log.info(f"  {rar}:")
        for ctype in ['BLEND', 'JP', 'EN']:
            if ctype in coefs:
                c = coefs[ctype]
                log.info(f"      {ctype:5s}: coef={c['coef']:.4f}  n_raw={c['n_raw']} n_filt={c['n_filtered']} iqr/med={c['iqr_over_median']:.3f}")

    # --- 메가리자몽 예시 ---
    mega_id = 'CRD_F95322AF0A1243D99F83'
    log.info(f"\n=== 메가리자몽X ex SAR 검증 ===")
    if mega_id in card_coefs:
        for ctype, info in card_coefs[mega_id].items():
            stored = info['coef'] * 1.0  # KO_ADJUSTMENT는 별도 (현재 raw coef만)
            log.info(f"  CARD {ctype:5s}: {info['coef']:.4f}  (n={info['n']})")
    else:
        log.info(f"  CARD coef 미달 (verified < 5 IQR pass) → RARITY fallback")

    if 'SAR' in rarity_coefs:
        log.info(f"  RARITY SAR fallback:")
        for ctype, info in rarity_coefs['SAR'].items():
            log.info(f"    {ctype:5s}: {info['coef']:.4f}")

    # --- INSERT ---
    if not args.apply:
        log.info("\n[dry-run] DB INSERT 생략. 적용하려면 --apply")
        conn.close()
        return

    log.info("\n=== DB INSERT ===")
    inserts = []
    # CARD
    for cid, coefs in card_coefs.items():
        rar = name_map.get(cid, (None, None))[1]
        for ctype, info in coefs.items():
            inserts.append((batch_id, 'CARD', cid, rar, None, ctype,
                            info['coef'], info['n'], info['iqr_over_median'],
                            data_source, f"NAVER+DAANGN bootstrap n={info['n']}",
                            now, expires_at))
    # RARITY
    for rar, coefs in rarity_coefs.items():
        for ctype, info in coefs.items():
            inserts.append((batch_id, 'RARITY', None, rar, None, ctype,
                            info['coef'], info['n_filtered'], info['iqr_over_median'],
                            data_source, f"NAVER+DAANGN time-weighted 7:3 n_raw={info['n_raw']} n_filt={info['n_filtered']}",
                            now, expires_at))

    cur.executemany("""
        INSERT INTO ko_price_coefficients
        (batch_id, scope, card_id, rarity, era, coef_type, coef, sample_count,
         iqr_over_median, data_source, source_desc, calculated_at, expires_at)
        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
    """, inserts)
    conn.commit()
    log.info(f"INSERT 완료: {len(inserts)} rows")
    conn.close()


if __name__ == '__main__':
    main()
