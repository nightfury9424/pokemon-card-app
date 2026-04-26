"""
네이버 쇼핑 검색 API 가격 수집기

- 현재 판매가 (listing price) 수집
- source = 'NAVER_SHOPPING'
- 고희귀도 카드만 대상 (시세 의미있는 카드)
"""

import time
import uuid
import re
import requests
import psycopg2
import psycopg2.extras
from datetime import datetime
from urllib.parse import quote

from config import DB_CONFIG, NAVER_CLIENT_ID, NAVER_CLIENT_SECRET, TARGET_RARITIES

NAVER_SHOP_URL = "https://openapi.naver.com/v1/search/shop.json"

NAVER_HEADERS = {
    "X-Naver-Client-Id": NAVER_CLIENT_ID,
    "X-Naver-Client-Secret": NAVER_CLIENT_SECRET,
    "User-Agent": "Mozilla/5.0",
}

# 카드 상태 키워드 판단
GRADED_KEYWORDS = ["psa", "bgs", "brg", "cgc", "sgc", "psg", "10등급", "9등급", "8등급", "등급"]


def strip_html(text: str) -> str:
    return re.sub(r"<[^>]+>", "", text)


def detect_card_status(title: str) -> tuple[str, str | None, str | None]:
    """
    상품명에서 카드 상태 추출
    'PSA 10등급' → ('GRADED', 'PSA', '10')
    그 외 → ('RAW', None, None)
    """
    title_lower = title.lower()

    for company in ["psa", "brg", "bgs", "cgc", "sgc", "psg"]:
        if company in title_lower:
            m = re.search(r"(\d+\.?\d*)\s*등급", title_lower)
            grade = m.group(1) if m else None
            return "GRADED", company.upper(), grade

    if any(k in title_lower for k in ["10등급", "9.5등급", "9등급", "8등급", "등급카드"]):
        m = re.search(r"(\d+\.?\d*)\s*등급", title_lower)
        grade = m.group(1) if m else None
        return "GRADED", "ETC", grade

    return "RAW", None, None


def search_naver(query: str, display: int = 10) -> list[dict]:
    """네이버 쇼핑 검색"""
    try:
        resp = requests.get(
            NAVER_SHOP_URL,
            params={"query": query, "display": display, "sort": "sim"},
            headers=NAVER_HEADERS,
            timeout=10
        )
        if resp.status_code == 200:
            return resp.json().get("items", [])
    except Exception as e:
        print(f"    [NAVER ERROR] {e}")
    return []


def already_collected_today(conn, card_id: str) -> bool:
    with conn.cursor() as cur:
        cur.execute("""
            SELECT 1 FROM price_snapshots
            WHERE card_id = %s AND source = 'NAVER_SHOPPING'
              AND collected_at > NOW() - INTERVAL '12 hours'
            LIMIT 1
        """, (card_id,))
        return cur.fetchone() is not None


def save_snapshot(conn, card_id: str, price: int, product_id: str,
                  title: str, source_url: str) -> bool:
    card_status, grading_company, grade_value = detect_card_status(title)
    snapshot_id = f"SNAP_{uuid.uuid4().hex[:20].upper()}"
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO price_snapshots
                  (price_snapshot_id, card_id, source, source_item_id, source_url,
                   price, currency, card_status, grading_company, grade_value,
                   traded_at, collected_at, created_at)
                VALUES (%s, %s, 'NAVER_SHOPPING', %s, %s, %s, 'KRW', %s, %s, %s,
                        NOW(), NOW(), NOW())
                ON CONFLICT DO NOTHING
            """, (snapshot_id, card_id, product_id, source_url, price,
                  card_status, grading_company, grade_value))
        conn.commit()
        return True
    except Exception as e:
        conn.rollback()
        print(f"    [DB ERROR] {e}")
        return False


def is_relevant(title: str, card_name: str) -> bool:
    """상품이 해당 카드와 관련있는지 확인 (노이즈 필터)"""
    title_clean = strip_html(title).lower()
    name_lower = card_name.lower()

    # 카드 이름 핵심어가 타이틀에 있어야 함
    core_name = re.sub(r"(ex|v|vmax|vstar|gx|ex)$", "", name_lower, flags=re.IGNORECASE).strip()
    if not core_name:
        return False

    return core_name in title_clean or fuzz_check(card_name, title_clean)


def fuzz_check(name: str, title: str) -> bool:
    from rapidfuzz import fuzz
    return fuzz.partial_ratio(name.lower(), title) >= 75


def collect():
    conn = psycopg2.connect(**DB_CONFIG)

    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        placeholders = ",".join(["%s"] * len(TARGET_RARITIES))
        cur.execute(f"""
            SELECT card_id, name, rarity_code, collection_number
            FROM cards
            WHERE rarity_code IN ({placeholders})
              AND language = 'KO'
            ORDER BY rarity_code, name
        """, TARGET_RARITIES)
        cards = cur.fetchall()

    print(f"[NAVER] 수집 대상: {len(cards)}장")

    saved = 0
    skipped = 0

    for i, card in enumerate(cards, 1):
        card_id = card['card_id']
        card_name = card['name']

        print(f"[{i}/{len(cards)}] {card_name} ({card['rarity_code']})", end=" ")

        if already_collected_today(conn, card_id):
            print("→ 오늘 이미 수집됨, 스킵")
            skipped += 1
            continue

        query = f"포켓몬카드 {card_name}"
        items = search_naver(query, display=10)

        count = 0
        for item in items:
            title = strip_html(item.get("title", ""))
            lprice = item.get("lprice")
            product_id = item.get("productId", "")
            link = item.get("link", "")

            if not lprice or int(lprice) <= 0:
                continue

            if not is_relevant(title, card_name):
                continue

            if save_snapshot(conn, card_id, int(lprice), product_id, title, link):
                count += 1
                saved += 1

        print(f"→ {count}건 저장")
        time.sleep(0.1)  # 네이버 API rate limit (초당 10회)

    print(f"\n[NAVER] 완료 | 저장: {saved}건, 스킵: {skipped}장")
    conn.close()


if __name__ == "__main__":
    collect()
