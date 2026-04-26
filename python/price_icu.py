"""
icu.gg (너정다) 가격 수집기

- icu.gg의 내부 API를 사용해 한국 카드 실거래가 수집
- card_state: S급/A급/B급/C급 → RAW, PSA/기타 등급 → GRADED
- 우리 DB 카드와 이름+번호 기준으로 매칭
"""

import time
import uuid
import requests
import psycopg2
import psycopg2.extras
from datetime import datetime
from rapidfuzz import fuzz

from config import DB_CONFIG, HEADERS, TARGET_RARITIES

ICU_BASE = "https://icu.gg"

GRADED_STATES = {"PSA", "BRG", "BGS", "CGC", "SGC", "ACE", "PSG", "기타"}

def parse_card_status(card_state: str) -> tuple[str, str | None, str | None]:
    """
    card_state → (card_status, grading_company, grade_value)
    예) 'PSA 10등급' → ('GRADED', 'PSA', '10')
         'S급' → ('RAW', None, None)
    """
    if not card_state:
        return "RAW", None, None

    state_upper = card_state.upper()
    for company in GRADED_STATES:
        if company in state_upper:
            # 등급 숫자 추출 (예: PSA 10등급 → 10, 기타 9.5등급 → 9.5)
            import re
            m = re.search(r"(\d+\.?\d*)\s*등급", card_state)
            grade = m.group(1) if m else None
            return "GRADED", company if company != "기타" else "ETC", grade

    return "RAW", None, None


def icu_post(endpoint: str, params: dict, retries: int = 2) -> list | dict | None:
    """icu.gg POST 요청"""
    url = f"{ICU_BASE}{endpoint}"
    for attempt in range(retries):
        try:
            resp = requests.post(url, json={"params": params}, headers=HEADERS, timeout=10)
            if resp.status_code == 200:
                return resp.json()
        except Exception as e:
            if attempt == retries - 1:
                print(f"    [ICU ERROR] {endpoint}: {e}")
        time.sleep(0.3)
    return None


def load_target_cards(conn) -> list[dict]:
    """수집 대상 카드 로드 (희귀도 필터)"""
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        placeholders = ",".join(["%s"] * len(TARGET_RARITIES))
        cur.execute(f"""
            SELECT card_id, name, collection_number, rarity_code
            FROM cards
            WHERE rarity_code IN ({placeholders})
              AND language = 'KO'
            ORDER BY rarity_code, name
        """, TARGET_RARITIES)
        return cur.fetchall()


def find_icu_card_id(card_name: str, collection_number: str) -> str | None:
    """
    카드 이름 + 번호로 icu.gg 카드 ID 검색
    icu의 trade rank에서 이름 퍼지 매칭
    """
    # 번호 앞부분만 추출 (예: 084/069 → 084)
    num_prefix = collection_number.split("/")[0].lstrip("0") if collection_number else ""

    data = icu_post("/api/rank/trade/kr", {
        "keyword": {"nation": "kr", "period": "all", "rarity": "", "series": ""}
    })
    if not data or not isinstance(data, list):
        return None

    best_score = 0
    best_id = None
    for card in data:
        icu_name = card.get("name", "")
        icu_num = str(card.get("number", "")).lstrip("0")

        name_score = fuzz.token_set_ratio(card_name, icu_name)
        num_match = (num_prefix and icu_num and num_prefix == icu_num)

        total = name_score * (1.5 if num_match else 1.0)
        if total > best_score and name_score >= 70:
            best_score = total
            best_id = card.get("id")

    return best_id


def already_collected_today(conn, card_id: str, source: str) -> bool:
    """오늘 이미 수집한 카드인지 확인 (중복 방지)"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT 1 FROM price_snapshots
            WHERE card_id = %s AND source = %s
              AND collected_at > NOW() - INTERVAL '12 hours'
            LIMIT 1
        """, (card_id, source))
        return cur.fetchone() is not None


def save_snapshot(conn, card_id: str, price: int, card_state: str,
                  source_item_id: str, traded_at: datetime) -> bool:
    card_status, grading_company, grade_value = parse_card_status(card_state)

    snapshot_id = f"SNAP_{uuid.uuid4().hex[:20].upper()}"
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO price_snapshots
                  (price_snapshot_id, card_id, source, source_item_id,
                   price, currency, card_status, grading_company, grade_value,
                   traded_at, collected_at, created_at)
                VALUES (%s, %s, 'ICU', %s, %s, 'KRW', %s, %s, %s, %s, NOW(), NOW())
                ON CONFLICT DO NOTHING
            """, (snapshot_id, card_id, source_item_id, price,
                  card_status, grading_company, grade_value, traded_at))
        conn.commit()
        return True
    except Exception as e:
        conn.rollback()
        print(f"    [DB ERROR] {e}")
        return False


def collect():
    conn = psycopg2.connect(**DB_CONFIG)
    cards = load_target_cards(conn)
    print(f"[ICU] 수집 대상: {len(cards)}장 (고희귀도)")

    # icu 전체 랭킹 한 번만 로드 (캐싱)
    print("[ICU] 전체 거래 랭킹 로드 중...")
    icu_rank = icu_post("/api/rank/trade/kr", {
        "keyword": {"nation": "kr", "period": "all", "rarity": "", "series": ""}
    }) or []

    # 이름 → icu_id 매핑 테이블 구성
    icu_map: dict[str, str] = {}
    for item in icu_rank:
        name = item.get("name", "")
        if name:
            icu_map[name] = item.get("id")

    saved = 0
    skipped = 0

    for i, card in enumerate(cards, 1):
        card_id = card['card_id']
        card_name = card['name']
        col_num = card['collection_number'] or ""

        print(f"[{i}/{len(cards)}] {card_name} ({card['rarity_code']})", end=" ")

        if already_collected_today(conn, card_id, "ICU"):
            print("→ 오늘 이미 수집됨, 스킵")
            skipped += 1
            continue

        # 이름 매칭으로 icu_id 찾기
        icu_id = None
        best_score = 0
        num_prefix = col_num.split("/")[0].lstrip("0") if col_num else ""

        for icu_name, iid in icu_map.items():
            score = fuzz.token_set_ratio(card_name, icu_name)
            if score > best_score and score >= 80:
                best_score = score
                icu_id = iid

        if not icu_id:
            print("→ icu 매칭 실패")
            continue

        # 거래 포스트 목록 가져오기
        posts = icu_post("/api/card/detail/trade/info/post_list", {
            "card_id": icu_id,
            "card_nation": "kr"
        })

        if not posts:
            print("→ 거래 데이터 없음")
            continue

        count = 0
        for post in posts:
            price = post.get("card_price")
            card_state = post.get("card_state", "S급")
            created = post.get("created")

            if not price or price <= 0:
                continue

            try:
                traded_at = datetime.fromisoformat(created.replace("Z", "+00:00"))
            except:
                traded_at = datetime.now()

            if save_snapshot(conn, card_id, price, card_state, str(icu_id), traded_at):
                count += 1
                saved += 1

        print(f"→ {count}건 저장")
        time.sleep(0.2)  # Rate limit

    print(f"\n[ICU] 완료 | 저장: {saved}건, 스킵: {skipped}장")
    conn.close()


if __name__ == "__main__":
    collect()
