"""
특수팩 전용 강제 수집 스크립트 (연도 기반 탐색)
- BS, SVP(일부), SMP(일부)는 이미 DB에 있으나 연도 기반 코드가 누락된 상태
- 패턴: {PREFIX}00{YEAR}{SEQ} (예: SVP002023009, SSP002021015)
- BS 시리즈와 동일한 연도별 분할 탐색 전략 적용
"""
import threading
from concurrent.futures import ThreadPoolExecutor
from psycopg2 import pool

import sync_cards

# ============================================================
# 수집 대상 시리즈 + 연도별 시작 번호
# BS와 동일한 규칙: {PREFIX} + 00 + {YEAR} + {SEQ(3자리~)}
# ============================================================
SPECIAL_SERIES_YEARS = []

PREFIXES = ["SVP", "SSP", "SMP", "XYP", "BWP", "ST", "SD", "MP", "PR", "CP", "PROMO"]

for prefix in PREFIXES:
    for year in range(2010, 2027):
        # 예: SVP002010001, SSP002023001...
        start = int(f"00{year}001")
        SPECIAL_SERIES_YEARS.append((prefix, start, 0))

MAX_WORKERS = 8


def main():
    print("=" * 70)
    print("🎯 [특수팩 연도 기반 전수조사 스크립트]")
    print(f"   대상 프리픽스: {', '.join(PREFIXES)}")
    print(f"   연도 범위: 2010 ~ 2026 (프리픽스당 17개 연도)")
    print(f"   총 탐색 시리즈: {len(SPECIAL_SERIES_YEARS)}개")
    print("=" * 70)

    sync_cards.db_pool = pool.ThreadedConnectionPool(1, MAX_WORKERS + 2, **sync_cards.DB_CONFIG)

    conn = sync_cards.db_pool.getconn()
    try:
        p_cols = sync_cards.get_products_table_columns(conn)
        c_cols = sync_cards.get_cards_table_columns(conn)
    finally:
        sync_cards.db_pool.putconn(conn)

    grand_total = 0

    try:
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for prefix, start_num, pad in SPECIAL_SERIES_YEARS:
                current_num = start_num
                consecutive_misses = 0
                found_count = 0

                while consecutive_misses < 200:
                    code = f"{prefix}{current_num}"

                    status = sync_cards.fetch_and_save(code, p_cols, c_cols)

                    if status not in ("NOT_FOUND", "NO_PRODUCT_NAME", "NO_CARD_NAME", "ERROR"):
                        consecutive_misses = 0
                        found_count += 1
                        if found_count == 1:
                            print(f"🎯 [{prefix}] 연도 {str(current_num)[2:6]} 첫 카드 발견: {code}")
                    else:
                        consecutive_misses += 1

                    current_num += 1

                if found_count > 0:
                    grand_total += found_count
                    print(f"   [{prefix}] 연도 {str(start_num)[2:6]} 완료 — {found_count}장 수집")

        # 최종 결과
        conn2 = sync_cards.db_pool.getconn()
        try:
            cur = conn2.cursor()
            cur.execute("""
                SELECT 
                    CASE 
                        WHEN official_card_code LIKE 'SVP%' THEN 'SVP'
                        WHEN official_card_code LIKE 'SSP%' THEN 'SSP'
                        WHEN official_card_code LIKE 'SMP%' THEN 'SMP'
                        WHEN official_card_code LIKE 'XYP%' THEN 'XYP'
                        WHEN official_card_code LIKE 'BWP%' THEN 'BWP'
                        WHEN official_card_code LIKE 'ST%' THEN 'ST'
                        WHEN official_card_code LIKE 'SD%' THEN 'SD'
                        WHEN official_card_code LIKE 'MP%' THEN 'MP'
                        WHEN official_card_code LIKE 'PR%' THEN 'PR'
                        WHEN official_card_code LIKE 'CP%' THEN 'CP'
                        WHEN official_card_code LIKE 'PROMO%' THEN 'PROMO'
                        ELSE 'MISC'
                    END AS prefix,
                    COUNT(*) AS cnt
                FROM cards
                WHERE official_card_code NOT LIKE 'BS%'
                GROUP BY prefix
                ORDER BY cnt DESC;
            """)
            rows = cur.fetchall()
            print("\n" + "=" * 70)
            print(f"📊 [특수팩 수집 최종 결과] (신규 {grand_total}장 추가)")
            for prefix, cnt in rows:
                print(f"   {prefix}: {cnt}장")
            print("=" * 70)
        finally:
            sync_cards.db_pool.putconn(conn2)

    finally:
        if sync_cards.db_pool:
            sync_cards.db_pool.closeall()


if __name__ == "__main__":
    main()
