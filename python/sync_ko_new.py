"""
KO 신규 고등급 카드 스크래퍼

기존 DB에 있는 마지막 카드 번호부터 이어서 스크랩.
고등급(SAR/SSR/CSR/CHR/ACE/BWR/RRR/UR/AR/SR/RR/PR/HR)만 DB에 저장.
저등급 카드는 페이지 존재 여부 탐지용으로만 사용(Jump Search 연속성 유지).

Usage: python sync_ko_new.py
"""

import re
import sys
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Optional, Set

import psycopg2
from psycopg2 import pool

import sync_cards

# ============================================================
# 고등급 필터
# ============================================================

HIGH_RARITY: Set[str] = {
    "SAR", "SSR", "CSR", "CHR", "ACE", "BWR", "RRR",
    "UR", "AR", "SR", "RR", "PR", "HR",
}

stats_lock = threading.Lock()
stats = {"inserted": 0, "skipped": 0, "rarity_skip": 0, "not_found": 0}


# ============================================================
# DB 헬퍼: 시리즈별 마지막 카드 번호 조회
# ============================================================

def get_last_num_in_db(conn, prefix: str, year: Optional[int] = None) -> Optional[int]:
    """DB에서 해당 시리즈/연도의 마지막 카드 번호 반환. 없으면 None."""
    if year is not None:
        like_pattern = f"{prefix}{year}%"
    else:
        like_pattern = f"{prefix}%"

    prefix_len = len(prefix)
    with conn.cursor() as cur:
        cur.execute(
            "SELECT official_card_code FROM cards WHERE official_card_code LIKE %s",
            (like_pattern,),
        )
        rows = cur.fetchall()

    if not rows:
        return None

    max_num = 0
    for (code,) in rows:
        try:
            num = int(code[prefix_len:])
            if num > max_num:
                max_num = num
        except ValueError:
            pass

    return max_num if max_num > 0 else None


# ============================================================
# 고등급 필터 포함 fetch_and_save
# ============================================================

def fetch_and_save_filtered(card_code: str, products_columns: Set[str], cards_columns: Set[str]) -> str:
    """
    페이지 파싱 후 고등급만 DB 저장.
    Returns:
      'OK'         - 고등급, 저장 완료
      'LOW_RARITY' - 저등급, 페이지는 존재 (probe 성공)
      'NOT_FOUND'  - 페이지 없음
      'ERROR'      - 파싱/DB 에러
    """
    try:
        status, incoming = sync_cards.parse_page(card_code)

        if status != "OK" or not incoming:
            with stats_lock:
                stats["not_found"] += 1
            return status

        rarity = incoming.get("rarity_code")
        if rarity not in HIGH_RARITY:
            print(f"[LOW_RARITY] {card_code} | {incoming['name']} | {rarity}")
            with stats_lock:
                stats["rarity_skip"] += 1
            return "LOW_RARITY"

        conn = sync_cards.db_pool.getconn()
        try:
            with sync_cards.product_lock:
                product, _ = sync_cards.insert_product_if_missing(
                    conn, incoming["product_name"], products_columns
                )
                conn.commit()

            incoming["product_id"] = product["product_id"]

            existing = sync_cards.find_existing_card(conn, incoming)
            if existing:
                print(f"[SKIP] {card_code} | {incoming['name']} | {rarity} (already in DB)")
                with stats_lock:
                    stats["skipped"] += 1
            else:
                sync_cards.insert_card(conn, incoming, cards_columns)
                print(f"[INSERT] {card_code} | {incoming['name']} | {rarity}")
                with stats_lock:
                    stats["inserted"] += 1
            conn.commit()
        except Exception as e:
            conn.rollback()
            print(f"[DB ERROR] {card_code}: {e}")
            return "ERROR"
        finally:
            sync_cards.db_pool.putconn(conn)

        return "OK"

    except Exception as e:
        print(f"[ERROR] {card_code}: {e}")
        return "ERROR"


# ============================================================
# 메인 스캔 루프
# ============================================================

def run():
    sync_cards.db_pool = pool.ThreadedConnectionPool(
        1, sync_cards.MAX_WORKERS + 2, **sync_cards.DB_CONFIG
    )

    conn = sync_cards.db_pool.getconn()
    try:
        products_columns = sync_cards.get_products_table_columns(conn)
        cards_columns = sync_cards.get_cards_table_columns(conn)

        # 시리즈별 시작 번호 계산
        series_starts = {}
        for prefix, default_start, pad in sync_cards.CARD_SERIES:
            if prefix == "BS":
                year = default_start // 1_000_000
                last = get_last_num_in_db(conn, prefix, year)
            else:
                last = get_last_num_in_db(conn, prefix)

            if last is not None:
                series_starts[(prefix, default_start, pad)] = last + 1
                label = f"BS{year}" if prefix == "BS" else prefix
                print(f"[RESUME] {label}: DB 마지막={last}, 이어서 {last+1}부터")
            else:
                series_starts[(prefix, default_start, pad)] = default_start
                label = f"BS{year}" if prefix == "BS" else prefix
                print(f"[NEW]    {label}: DB 없음, {default_start}부터 시작")
    finally:
        sync_cards.db_pool.putconn(conn)

    print(f"\n{'='*80}")
    print("🚀 고등급 KO 카드 신규 스크래퍼 시작")
    print(f"   대상 등급: {', '.join(sorted(HIGH_RARITY))}")
    print(f"{'='*80}\n")

    with ThreadPoolExecutor(max_workers=sync_cards.MAX_WORKERS) as executor:
        for prefix, default_start, pad in sync_cards.CARD_SERIES:
            start_num = series_starts[(prefix, default_start, pad)]

            # BS 시리즈: 연도 경계를 넘지 않도록 제한
            if prefix == "BS":
                year = default_start // 1_000_000
                year_end = (year + 1) * 1_000_000
            else:
                year = None
                year_end = None

            label = f"BS{year}" if year else prefix
            print(f"\n[SERIES START] {label} — {start_num}부터")

            current_num = start_num
            void_distance = 0
            max_void = 10_000
            known_results: dict = {}

            def process_num(num: int, _prefix=prefix, _pad=pad, _ye=year_end) -> bool:
                if num in known_results:
                    return known_results[num]
                if _ye is not None and num >= _ye:
                    known_results[num] = False
                    return False

                num_str = str(num).zfill(_pad) if _pad > 0 else str(num)
                code = f"{_prefix}{num_str}"
                result = fetch_and_save_filtered(code, products_columns, cards_columns)
                # LOW_RARITY = 페이지 존재 → probe 성공
                success = result not in ("NOT_FOUND", "NO_PRODUCT_NAME", "NO_CARD_NAME", "ERROR")
                known_results[num] = success
                return success

            while void_distance < max_void:
                step = 10 if void_distance < 50_000 else 100

                if process_num(current_num):
                    void_distance = 0

                    # Backfill: 건너뛴 구간 병렬 수집
                    if current_num > start_num:
                        bf_start = max(start_num, current_num - step + 1)
                        bf_end = current_num - 1
                        if bf_end >= bf_start:
                            futs = [executor.submit(process_num, n) for n in range(bf_start, bf_end + 1)]
                            for f in futs:
                                f.result()

                    # Forward scan: 연속 4회 실패 시 구간 종료
                    current_num += 1
                    misses = 0
                    while misses < 4:
                        chunk = list(range(current_num, current_num + 4))
                        futs = [executor.submit(process_num, n) for n in chunk]
                        for fut in futs:
                            ok = fut.result()
                            misses = 0 if ok else misses + 1
                            current_num += 1
                            if misses >= 4:
                                break

                    current_num += step
                else:
                    void_distance += step
                    current_num += step

            print(f"[SERIES END] {label} 완료 (빈 구간 {max_void}개 도달)")

    print(f"\n{'='*80}")
    print(f"✅ 완료 | 신규={stats['inserted']}, 이미있음={stats['skipped']}, 저등급스킵={stats['rarity_skip']}, 없음={stats['not_found']}")
    print(f"{'='*80}")

    # 매핑 대기 중인 미매핑 카드 수 확인
    conn = sync_cards.db_pool.getconn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT COUNT(*) FROM cards
                WHERE language = 'KO'
                  AND rarity_code IN ('SSR','SAR','BWR','CSR','CHR','UR','SR','AR','HR','ACE','RRR','RR','PR','SM-P')
                  AND (jp_scrydex_ref IS NULL OR jp_scrydex_ref LIKE 'NO_%%')
                  AND (en_scrydex_ref IS NULL OR en_scrydex_ref LIKE 'NO_%%')
            """)
            unmapped_count = cur.fetchone()[0]
    finally:
        sync_cards.db_pool.putconn(conn)

    print(f"\n🗺️  JP/EN 매핑 대기: {unmapped_count}장")
    print(f"   → 스캐너 실행 후 아래 파일 열기:")
    print(f"   open /Users/fury/pokemon-card-app/scanner/data/scrydex_mapper.html")

    sync_cards.db_pool.closeall()


if __name__ == "__main__":
    run()
