"""
=================================================================
포켓몬 카드 100% 전수조사 크롤러 (AJAX API 직접 호출)
=================================================================
포켓몬코리아 홈페이지의 숨겨진 AJAX API를 직접 호출하여
이 세상에 존재하는 모든 카드 코드를 100% 수집합니다.

사용법:
  python3 sync_all.py          # 신규/변경 카드만 추가 (기존 데이터 유지)
  python3 sync_all.py --reset  # DB 초기화 후 처음부터 전수조사
=================================================================
"""
import re
import sys
import time
import threading
import json
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
import psycopg2
from psycopg2 import pool

import sync_cards  # 기존 파서 & DB 로직 재사용

# ============================================================
# 설정
# ============================================================
MAX_WORKERS = 8
AJAX_URL = "https://pokemoncard.co.kr/v2/ajax2_dev2"
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/123.0.0.0 Safari/537.36"
    ),
    "Referer": "https://pokemoncard.co.kr/cards",
    "X-Requested-With": "XMLHttpRequest",
}

# 모든 필터를 '전체'로 설정 → 누락 0%
FULL_FILTER_DATA = {
    "GoodsName": "전체",
    "CardTypeNum": "1",
    "CardMonType": "풀,불꽃,물,번개,초,격투,악,강철,페어리,드래곤,무색,all",
    "Weakness": "풀,불꽃,물,번개,초,격투,악,강철,페어리,드래곤,무색,all",
    "Resistance": "풀,불꽃,물,번개,초,격투,악,강철,페어리,드래곤,무색,all",
    "TechErg": "풀,불꽃,물,번개,초,격투,악,강철,페어리,드래곤,무색,all",
    "hp": "0,380",
    "retreat": "0,5",
    "order": "DESC",
    "orderby": "order_num",
    "CardType": "",
    "ability_label1": "",
}


# ============================================================
# STEP 1: 숨겨진 AJAX API로 모든 카드 코드 100% 수집
# ============================================================
def scrape_all_card_codes():
    session = requests.Session()

    # 세션 쿠키(PHPSESSID) 획득
    print("\n📡 [STEP 1] 포켓몬코리아 세션 쿠키 획득 중...")
    session.get("https://pokemoncard.co.kr/cards", headers=HEADERS, timeout=15)
    print("   ✅ 세션 쿠키 획득 완료!")

    all_codes = []
    limit = 0
    empty_streak = 0

    print("\n🔍 [STEP 2] AJAX API 전수조사 시작 (30장씩 로드)...\n")

    while empty_streak < 10:
        # 첫 호출은 search_text_cards, 이후는 get_more_cards
        if limit == 0:
            data = {
                "action": "search_text_cards",
                "search_text": "",
                "search_params": "all",
                "limit": str(limit),
            }
        else:
            data = {
                "action": "get_more_cards",
                "limit": str(limit),
                **FULL_FILTER_DATA,
            }

        try:
            res = session.post(AJAX_URL, data=data, headers=HEADERS, timeout=15)
            body = res.json()

            result = body.get("result", {})
            if not result or not isinstance(result, dict) or len(result) == 0:
                empty_streak += 1
                limit += 1
                continue

            empty_streak = 0
            batch_codes = []
            for key, card in result.items():
                card_num = card.get("CardNum")
                if card_num:
                    # [버그수정] AJAX는 같은 카드를 'BS123m' 형태로 중복 반환함
                    # 'm' 접미사를 제거하여 정규화
                    clean_num = card_num.rstrip('m') if card_num.endswith('m') else card_num
                    if clean_num not in batch_codes:
                        batch_codes.append(clean_num)
                        all_codes.append(clean_num)

            if (limit + 1) % 20 == 0:
                print(f"   ... {(limit+1)*30}장 로드 완료 (누적 {len(all_codes)}장)")

        except Exception as e:
            print(f"   ⚠️  limit={limit} 오류: {e}")
            empty_streak += 1

        limit += 1
        time.sleep(0.05)

    print(f"\n   ✅ AJAX 스캔 완료! 총 카드 코드: {len(all_codes)}장")

    # 프리픽스별 통계
    prefix_counts = {}
    for code in all_codes:
        m = re.match(r"([A-Za-z]+)", code)
        if m:
            p = m.group(1)
            prefix_counts[p] = prefix_counts.get(p, 0) + 1
    print("\n   [프리픽스별 분포]")
    for p, cnt in sorted(prefix_counts.items(), key=lambda x: -x[1]):
        print(f"     {p}: {cnt}장")

    return all_codes


# ============================================================
# DB 초기화 (--reset 옵션)
# ============================================================
def reset_db():
    print("\n🗑️  [DB 초기화] cards, products 테이블 전체 삭제 중...")
    conn = psycopg2.connect(**sync_cards.DB_CONFIG)
    conn.autocommit = True
    cur = conn.cursor()
    cur.execute("TRUNCATE TABLE cards CASCADE;")
    cur.execute("TRUNCATE TABLE products CASCADE;")
    conn.close()
    print("   ✅ DB 초기화 완료!")


# ============================================================
# STEP 3: 상세 페이지 병렬 크롤링 → DB 저장
# ============================================================
def sync_all_cards(card_codes):
    sync_cards.db_pool = pool.ThreadedConnectionPool(1, MAX_WORKERS + 2, **sync_cards.DB_CONFIG)

    conn = sync_cards.db_pool.getconn()
    try:
        p_cols = sync_cards.get_products_table_columns(conn)
        c_cols = sync_cards.get_cards_table_columns(conn)

        cur = conn.cursor()
        cur.execute("SELECT official_card_code FROM cards")
        existing = {row[0] for row in cur.fetchall()}
    finally:
        sync_cards.db_pool.putconn(conn)

    new_codes = [c for c in card_codes if c not in existing]
    skip_count = len(card_codes) - len(new_codes)

    print(f"\n🚀 [STEP 3] 상세 페이지 병렬 크롤링 시작!")
    print(f"   전체: {len(card_codes)}장 | 이미 DB: {skip_count}장 | 신규: {len(new_codes)}장")

    if not new_codes:
        print("   🎉 모든 카드가 이미 DB에 있습니다!")
        return

    done = {"ok": 0, "fail": 0}
    lock = threading.Lock()
    total = len(new_codes)

    def process(code):
        status = sync_cards.fetch_and_save(code, p_cols, c_cols)
        with lock:
            if status not in ("NOT_FOUND", "NO_PRODUCT_NAME", "NO_CARD_NAME", "ERROR"):
                done["ok"] += 1
            else:
                done["fail"] += 1
            progress = done["ok"] + done["fail"]
            if progress % 200 == 0:
                print(f"   [{progress}/{total}] 성공: {done['ok']} | 실패: {done['fail']}")

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [executor.submit(process, code) for code in new_codes]
        for f in as_completed(futures):
            f.result()

    print(f"\n   ✅ 완료! 성공: {done['ok']}장 | 실패: {done['fail']}장")

    # 최종 DB 통계
    conn2 = sync_cards.db_pool.getconn()
    try:
        cur = conn2.cursor()
        cur.execute("""
            SELECT 
                REGEXP_REPLACE(official_card_code, '[0-9].*', '') AS prefix,
                COUNT(*) AS cnt
            FROM cards
            GROUP BY prefix
            ORDER BY cnt DESC;
        """)
        rows = cur.fetchall()
        total_db = sum(cnt for _, cnt in rows)
        print("\n" + "=" * 60)
        print(f"📊 [최종 DB 카드 현황] 총 {total_db}장")
        for prefix, cnt in rows:
            print(f"   {prefix}: {cnt}장")
        print("=" * 60)
    finally:
        sync_cards.db_pool.putconn(conn2)
    # Phase 2에서 재사용할 수 있도록 pool을 여기서 닫지 않음


# ============================================================
# Main
# ============================================================
def main():
    print("=" * 60)
    print("🏆 포켓몬 카드 100% 전수조사 크롤러 (AJAX + Jump Search)")
    print("=" * 60)

    if "--reset" in sys.argv:
        reset_db()

    # ============================================================
    # Phase 1: AJAX API로 공개 목록 수집
    # ============================================================
    print("\n📋 [Phase 1] AJAX API — 공식 홈페이지 전체 목록 수집")
    card_codes = scrape_all_card_codes()

    if card_codes:
        sync_all_cards(card_codes)

    # ============================================================
    # Phase 2: Jump Search 보완 — AJAX가 놓친 SAR/AR/CSR 고번호 카드 수집
    # ============================================================
    print("\n\n🔍 [Phase 2] Jump Search 보완 — AJAX 누락 고번호 카드(SAR/AR/CSR) 수집")
    print("   (이미 DB에 있는 카드는 자동 스킵됩니다)")

    # Phase 1이 닫았을 수도 있으므로 항상 새로 생성
    sync_cards.db_pool = pool.ThreadedConnectionPool(1, MAX_WORKERS + 2, **sync_cards.DB_CONFIG)

    conn = sync_cards.db_pool.getconn()
    try:
        p_cols = sync_cards.get_products_table_columns(conn)
        c_cols = sync_cards.get_cards_table_columns(conn)
    finally:
        sync_cards.db_pool.putconn(conn)

    try:
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for prefix, start_num, pad in sync_cards.CARD_SERIES:
                print(f"\n   [JUMP] {prefix} 시리즈 보완 탐색...")
                current_num = start_num
                void_distance = 0
                max_void = 100000
                known_results = {}

                def process_num(num):
                    if num in known_results:
                        return known_results[num]
                    num_str = str(num).zfill(pad) if pad > 0 else str(num)
                    code = f"{prefix}{num_str}"
                    status = sync_cards.fetch_and_save(code, p_cols, c_cols)
                    success = status not in ("NOT_FOUND", "NO_PRODUCT_NAME", "NO_CARD_NAME", "ERROR")
                    known_results[num] = success
                    return success

                while void_distance < max_void:
                    step = 10 if void_distance < 50000 else 100
                    if process_num(current_num):
                        void_distance = 0
                        if current_num > start_num:
                            backfill_start = max(start_num, current_num - step + 1)
                            backfill_end = current_num - 1
                            if backfill_end >= backfill_start:
                                futures = [executor.submit(process_num, n)
                                           for n in range(backfill_start, backfill_end + 1)]
                                for f in futures:
                                    f.result()

                        # 발견 지점부터 빈칸 4번까지 순차 정밀 탐색
                        current_num += 1
                        misses = 0
                        while misses < 4:
                            chunk = list(range(current_num, current_num + 4))
                            futures = [executor.submit(process_num, n) for n in chunk]
                            for f in futures:
                                if f.result():
                                    misses = 0
                                else:
                                    misses += 1
                                current_num += 1
                                if misses >= 4:
                                    break
                        current_num += step
                    else:
                        void_distance += step
                        current_num += step

                print(f"   [DONE] {prefix} 완료")
    finally:
        if sync_cards.db_pool:
            sync_cards.db_pool.closeall()

    # 최종 통계
    final_conn = psycopg2.connect(**sync_cards.DB_CONFIG)
    cur = final_conn.cursor()
    cur.execute("""
        SELECT REGEXP_REPLACE(official_card_code, '[0-9].*', '') AS prefix,
               COUNT(*) AS cnt
        FROM cards GROUP BY prefix ORDER BY cnt DESC;
    """)
    rows = cur.fetchall()
    total = sum(c for _, c in rows)
    final_conn.close()

    print("\n" + "=" * 60)
    print(f"🎉 [전수조사 완료] 총 {total}장")
    for p, c in rows:
        print(f"   {p}: {c}장")
    print("=" * 60)


if __name__ == "__main__":
    main()

