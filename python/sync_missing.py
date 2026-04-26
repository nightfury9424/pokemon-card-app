import sys
import os
import re
import urllib.request
from concurrent.futures import ThreadPoolExecutor
import psycopg2
from psycopg2 import pool

# 기존 sync_cards.py 의 검증된 DB 풀링 및 파서 함수 재사용
import sync_cards

def get_db_codes():
    conn = psycopg2.connect(**sync_cards.DB_CONFIG)
    cur = conn.cursor()
    cur.execute("SELECT official_card_code FROM cards")
    codes = {row[0] for row in cur.fetchall()}
    conn.close()
    return codes

def fetch_page_codes(page_num):
    url = f"https://pokemoncard.co.kr/cards?page={page_num}"
    try:
        req = urllib.request.Request(url, headers=sync_cards.HEADERS)
        html = urllib.request.urlopen(req, timeout=10).read().decode('utf-8')
        # [버그 수정] 웹사이트의 HTML 태그는 goDetail()이 아니라 <a href="/cards/detail/XXX"> 형식임
        return set(re.findall(r"/cards/detail/([A-Za-z0-9_-]+)", html))
    except Exception:
        return set()

def main():
    print("="*60)
    print("🚀 [특수팩 결측치 전수조사 수집 스크립트 시작]")
    print("="*60)
    
    print("1. DB에 저장된 기존 카드 조회 중...")
    db_codes = get_db_codes()
    print(f"   -> 기존 보관 카드: {len(db_codes)}장")
    
    print("\n2. 포켓몬코리아 전체 리스트 순차 스크래핑 중...")
    print("   (서버 Rate Limit 회피를 위해 순차적으로 진행합니다)")
    web_codes = set()
    empty_streak = 0
    page = 1
    
    while empty_streak < 5:
        codes = fetch_page_codes(page)
        if codes:
            web_codes.update(codes)
            empty_streak = 0
            if page % 50 == 0:
                print(f"   ... {page}페이지 완료 (누적 {len(web_codes)}장)")
        else:
            empty_streak += 1
        page += 1
        import time
        time.sleep(0.1)  # 서버 부하 방지용 0.1초 쿨타임
            
    print(f"   -> 총 {page-1}페이지 스캔 완료, 공식 홈페이지 전체 카드 수: {len(web_codes)}장")
    
    missing_codes = web_codes - db_codes
    print(f"\n3. DB 누락(MP, PR 등 비정규코드) 카드 발견: {len(missing_codes)}장!")
    
    if not missing_codes:
        print("🎉 모든 카드가 완벽하게 동기화되어 있습니다!")
        return
        
    print("\n4. 누락 카드 즉시 동기화 다운로드 시작...")
    # 커넥션 풀 초기화
    sync_cards.db_pool = pool.ThreadedConnectionPool(1, sync_cards.MAX_WORKERS + 2, **sync_cards.DB_CONFIG)
    
    conn = sync_cards.db_pool.getconn()
    try:
        p_cols = sync_cards.get_products_table_columns(conn)
        c_cols = sync_cards.get_cards_table_columns(conn)
    finally:
        sync_cards.db_pool.putconn(conn)
        
    def process_missing(code):
        sync_cards.fetch_and_save(code, p_cols, c_cols)
        
    with ThreadPoolExecutor(max_workers=sync_cards.MAX_WORKERS) as ex:
        ex.map(process_missing, list(missing_codes))
        
    print("\n✅ 모든 결측치(MP, PR 등) 수집 처리가 완료되었습니다!")

if __name__ == "__main__":
    main()
