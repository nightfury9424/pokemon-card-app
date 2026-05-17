import re
import time
import uuid
import threading
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional, Set, Tuple

import psycopg2
import psycopg2.extras
from psycopg2 import pool
import requests
from bs4 import BeautifulSoup

# ============================================================
# 설정
# ============================================================

BASE_URL = "https://pokemoncard.co.kr"

HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/123.0.0.0 Safari/537.36"
    )
}

DB_CONFIG = {
    "host": "localhost",
    "port": 5432,
    "dbname": "pokemon_card_db",
    "user": "nightfury",
    "password": "",
}

CARD_SERIES = [
    # ---- 일반 확장팩 (BS) 연도별 강제 분할 (거대 갭 스킵) ----
    ("BS", 2010000001, 0),
    ("BS", 2011000001, 0),
    ("BS", 2012000001, 0),
    ("BS", 2013000001, 0),
    ("BS", 2014000001, 0),
    ("BS", 2015000001, 0),
    ("BS", 2016000001, 0),
    ("BS", 2017000001, 0),
    ("BS", 2018000001, 0),
    ("BS", 2019000001, 0),
    ("BS", 2020000001, 0),
    ("BS", 2021000001, 0),
    ("BS", 2022000001, 0),
    ("BS", 2023000001, 0),
    ("BS", 2024000001, 0),
    ("BS", 2025000001, 0),
    ("BS", 2026000001, 0),
    
    # ---- 각종 프로모 & 덱 등 스페셜 팩 시리즈 ----
    ("SVP", 1, 9),          # 스칼렛&바이올렛 프로모
    ("SSP", 1, 9),          # 소드&실드 프로모
    ("SMP", 1, 9),          # 썬&문 프로모
    ("XYP", 1, 9),          # XY 프로모
    ("BWP", 1, 9),          # BW 프로모
    ("ST", 1, 9),           # 스타터 덱 / 스타트 덱
    ("SD", 1, 9),           # 스페셜 덱
    ("MP", 1, 9),           # 메가팩
    ("PR", 1, 9),           # 프로모 기획 제품
    ("CP", 1, 9),           # 컨셉 팩
    ("PROMO", 1, 9),        # 옛날 영문 프로모
]

MAX_WORKERS = 8      # 포켓몬 코리아 서버 부하를 고려해 적절한 스레드 수 유지
DEFAULT_LANGUAGE = "KO"

FOOTER_KEYWORDS = [
    "회사소개", "사업내용", "제휴안내", "이용약관", "개인정보처리방침",
    "이메일무단수집거부", "대한민국 내 대리인 안내", "고객센터", "go top",
    "관련카드", "로그인", "카드검색", "새소식", "제품정보", "놀이방법",
    "이벤트", "덱레시피", "플레이어즈", "예약", "포켓몬 도감에서 알아보기"
]

RARITY_CANDIDATES = [
    "SAR", "SSR", "CSR", "CHR", "ACE", "BWR", "RRR", "UR", "AR", "SR",
    "RR", "PR", "HR", "H", "R", "U", "C"
]

# DB Connection Pool & Locks
db_pool = None
product_lock = threading.Lock()
stats_lock = threading.Lock()

stats = {
    "inserted": 0, "updated": 0, "skipped": 0,
    "not_found": 0, "no_product_name": 0, "no_card_name": 0,
    "product_backfilled": 0
}


# ============================================================
# 공통 유틸
# ============================================================

def clean_text(text: Optional[str]) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


def build_detail_url(card_code: str) -> str:
    return f"{BASE_URL}/cards/detail/{card_code}"


def fetch_html(url: str, timeout: int = 15) -> Optional[str]:
    try:
        response = requests.get(url, headers=HEADERS, timeout=timeout)
        if response.status_code == 404:
            return None
        response.raise_for_status()
        return response.text
    except requests.RequestException:
        return None


def generate_card_id() -> str:
    return f"CRD_{uuid.uuid4().hex[:20].upper()}"


def generate_product_id() -> str:
    return f"PRD_{uuid.uuid4().hex[:20].upper()}"


def extract_lines(soup: BeautifulSoup) -> List[str]:
    text = soup.get_text("\n", strip=True)
    lines = [clean_text(line) for line in text.splitlines()]
    return [line for line in lines if line]


def looks_like_footer_or_noise(text: str) -> bool:
    return any(keyword in text for keyword in FOOTER_KEYWORDS)


def parse_collection_number(soup: BeautifulSoup) -> Optional[str]:
    p_num = soup.find("span", class_="p_num")
    if p_num:
        text = p_num.get_text(" ", strip=True)
        m = re.search(r"\b(\d{1,3}/\d{1,3})\b", text)
        if m:
            return m.group(1)
    
    # Fallback
    text = soup.get_text(" ", strip=True)
    m = re.search(r"\b(\d{1,3}/\d{1,3})\b", text)
    if m:
        return m.group(1)
    return None


def parse_rarity_code(soup: BeautifulSoup) -> Optional[str]:
    p_num = soup.find("span", class_="p_num")
    if p_num:
        no_wrap = p_num.find("span", id="no_wrap_by_admin")
        if no_wrap:
            text = clean_text(no_wrap.get_text()).upper()
            if text in RARITY_CANDIDATES:
                return text
        
        text = p_num.get_text(" ", strip=True)
        m = re.search(r"\b\d{1,3}/\d{1,3}\s*([A-Za-z]{1,3})\b", text)
        if m:
            candidate = m.group(1).upper()
            if candidate in RARITY_CANDIDATES:
                return candidate

    page_text = soup.get_text(" ", strip=True)
    m = re.search(r"\b\d{1,3}/\d{1,3}\s*([A-Za-z]{1,3})\b", page_text)
    if m:
        candidate = m.group(1).upper()
        if candidate in RARITY_CANDIDATES:
            return candidate

    for rarity in RARITY_CANDIDATES:
        if re.search(rf"(?<![A-Za-z]){re.escape(rarity)}(?![A-Za-z])", page_text):
            return rarity

    return None


def parse_illustrator(lines: List[str]) -> Optional[str]:
    for i, line in enumerate(lines):
        if line == "일러스트" and i + 1 < len(lines):
            nxt = clean_text(lines[i + 1])
            if nxt and not looks_like_footer_or_noise(nxt):
                return nxt

    page_text = " ".join(lines)
    patterns = [
        r"(?:일러스트|일러스트레이터)\s*[:：]?\s*([A-Za-z0-9가-힣&.\- ']+)",
        r"Illus\.\s*([A-Za-z0-9가-힣&.\- ']+)",
    ]
    for pattern in patterns:
        m = re.search(pattern, page_text)
        if m:
            return clean_text(m.group(1))
    return None


def parse_card_types(page_text: str) -> Tuple[str, Optional[str]]:
    # 포켓몬 카드는 항상 HP + (약점 또는 저항) 보유 → 먼저 체크해야 오분류 방지
    if "HP" in page_text and ("약점" in page_text or "저항" in page_text):
        if "레벨업" in page_text: return "POKEMON", "LEVEL_UP"
        if "포켓몬 ex" in page_text: return "POKEMON", "EX"
        if "2진화" in page_text: return "POKEMON", "STAGE2"
        if "1진화" in page_text: return "POKEMON", "STAGE1"
        if "기본 포켓몬" in page_text: return "POKEMON", "BASIC"
        return "POKEMON", None
    if "포켓몬의 도구" in page_text: return "TRAINER", "TOOL"
    if "서포트" in page_text: return "TRAINER", "SUPPORTER"
    if "아이템" in page_text: return "TRAINER", "ITEM"
    if "스타디움" in page_text: return "TRAINER", "STADIUM"
    if "특수 에너지" in page_text: return "ENERGY", "SPECIAL"
    if "기본 에너지" in page_text: return "ENERGY", "BASIC"
    return "POKEMON", None


# ============================================================
# 카드명 / 팩명 파싱
# ============================================================

def normalize_card_name(name: str) -> str:
    name = clean_text(name)
    name = re.sub(r"\s+L[Vv]\.?\s*[0-9Xx.]+$", "", name).strip()
    name = re.sub(r"\s+LV\.?\s*[0-9Xx.]+$", "", name).strip()
    return name


def parse_card_name(soup: BeautifulSoup) -> str:
    title_span = soup.find("span", class_="card-hp title")
    if title_span:
        name = clean_text(title_span.get_text())
        if name:
            return normalize_card_name(name)
    return ""


def normalize_product_name(raw_name: str) -> str:
    name = clean_text(raw_name)
    stop_keywords = [
        "관련카드", "회사소개", "사업내용", "제휴안내", "이용약관",
        "개인정보처리방침", "이메일무단수집거부", "대한민국 내 대리인 안내",
        "고객센터", "go top", "No.", "키 :", "키:", "몸무게 :", "몸무게:",
        "포켓몬 도감에서 알아보기"
    ]
    for keyword in stop_keywords:
        idx = name.find(keyword)
        if idx != -1:
            name = clean_text(name[:idx])
    return name


def extract_product_name(soup: BeautifulSoup) -> Optional[str]:
    detail_div = soup.find("div", class_="pokemon-detail txt_centre")
    if detail_div:
        a_tag = detail_div.find("a", class_="search_href")
        if a_tag:
            name = normalize_product_name(a_tag.get_text())
            if name: return name
    return None


def parse_series_name(product_name: str) -> str:
    m = re.match(
        r"^(.*?)\s+(확장팩|강화 확장팩|하이클래스팩|스타트 덱|스타터 덱|구축덱|배틀덱)",
        product_name,
    )
    if m:
        return clean_text(m.group(1))
    return ""


def parse_product_type(product_name: str) -> str:
    if "하이클래스팩" in product_name: return "HIGH_CLASS_PACK"
    if "강화 확장팩" in product_name: return "ENHANCED_BOOSTER"
    if "확장팩" in product_name: return "BOOSTER"
    if any(k in product_name for k in ["스타터 덱", "스타트 덱", "구축덱", "배틀덱"]): return "DECK"
    return "SPECIAL"


def parse_image_url(soup: BeautifulSoup) -> str:
    feature_image = soup.find("img", class_="feature_image")
    if feature_image and feature_image.get("src"):
        src = feature_image["src"]
        return src if src.startswith("http") else f"{BASE_URL}{src}"

    og_image = soup.find("meta", property="og:image")
    if og_image and og_image.get("content"):
        return clean_text(og_image["content"])

    img = soup.find("img")
    if img and img.get("src"):
        src = img["src"]
        return src if src.startswith("http") else f"{BASE_URL}{src}"

    return ""


# ============================================================
# DB Layer
# ============================================================

def get_products_table_columns(conn) -> Set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name = 'products'")
        return {row[0] for row in cur.fetchall()}


def get_cards_table_columns(conn) -> Set[str]:
    with conn.cursor() as cur:
        cur.execute("SELECT column_name FROM information_schema.columns WHERE table_name = 'cards'")
        return {row[0] for row in cur.fetchall()}


def find_product_by_name(conn, product_name: str) -> Optional[Dict]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("""
            SELECT * FROM products WHERE name = %s AND language = %s LIMIT 1
        """, (product_name, DEFAULT_LANGUAGE))
        return cur.fetchone()


def insert_product_if_missing(conn, product_name: str, products_columns: Set[str]) -> Tuple[Dict, bool]:
    existing = find_product_by_name(conn, product_name)
    if existing:
        return existing, False

    product_id = generate_product_id()
    data = {
        "product_id": product_id,
        "name": product_name,
        "series_name": parse_series_name(product_name),
        "product_type": parse_product_type(product_name),
        "language": DEFAULT_LANGUAGE,
        "image_url": None,
    }

    filtered = {k: v for k, v in data.items() if k in products_columns}
    columns = list(filtered.keys())
    values = list(filtered.values())
    placeholders = ["%s"] * len(columns)

    query = f"""
        INSERT INTO products ({", ".join(columns)}, created_at, updated_at)
        VALUES ({", ".join(placeholders)}, NOW(), NOW())
    """
    with conn.cursor() as cur:
        cur.execute(query, values)

    return data, True


def find_existing_card(conn, incoming: Dict) -> Optional[Dict]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute("SELECT * FROM cards WHERE official_card_code = %s LIMIT 1", (incoming["official_card_code"],))
        row = cur.fetchone()
        if row: return row

        if incoming.get("product_id") and incoming.get("collection_number"):
            cur.execute("""
                SELECT * FROM cards WHERE product_id = %s AND collection_number = %s LIMIT 1
            """, (incoming["product_id"], incoming["collection_number"]))
            row = cur.fetchone()
            if row: return row

        return None


def needs_update(existing: Dict, incoming: Dict) -> bool:
    fields = [
        "product_id", "official_card_code", "name", "collection_number",
        "card_number", "rarity_code", "language", "super_type", 
        "sub_type", "illustrator", "image_url", "official_url"
    ]
    for field in fields:
        old_val = clean_text(str(existing.get(field) or ""))
        new_val = clean_text(str(incoming.get(field) or ""))
        if old_val != new_val:
            return True
    return False


def insert_card(conn, incoming: Dict, cards_columns: Set[str]) -> str:
    card_id = generate_card_id()
    data = {**incoming, "card_id": card_id}
    
    filtered = {k: v for k, v in data.items() if k in cards_columns}
    columns = list(filtered.keys())
    values = list(filtered.values())
    placeholders = ["%s"] * len(columns)

    query = f"""
        INSERT INTO cards ({", ".join(columns)}, created_at, updated_at)
        VALUES ({", ".join(placeholders)}, NOW(), NOW())
    """
    with conn.cursor() as cur:
        cur.execute(query, values)
    return card_id


def update_card(conn, card_id: str, incoming: Dict, cards_columns: Set[str]) -> None:
    with conn.cursor() as cur:
        cur.execute("SELECT name_locked FROM cards WHERE card_id = %s", (card_id,))
        row = cur.fetchone()
        name_locked = row[0] if row else False

    assignments = []
    values = []
    for key, value in incoming.items():
        if key in cards_columns and key != "card_id":
            if key == "name" and name_locked:
                continue
            assignments.append(f"{key} = %s")
            values.append(value)

    assignments.append("updated_at = NOW()")
    values.append(card_id)

    query = f"UPDATE cards SET {', '.join(assignments)} WHERE card_id = %s"
    with conn.cursor() as cur:
        cur.execute(query, values)


# ============================================================
# 상세 페이지 파싱 & 저장
# ============================================================

def parse_page(card_code: str) -> Tuple[str, Optional[Dict]]:
    detail_url = build_detail_url(card_code)
    html = fetch_html(detail_url)
    if html is None:
        return "NOT_FOUND", None

    soup = BeautifulSoup(html, "html.parser")
    lines = extract_lines(soup)
    page_text = " ".join(lines)

    product_name = extract_product_name(soup)
    if not product_name:
        return "NO_PRODUCT_NAME", None

    card_name = parse_card_name(soup)
    if not card_name:
        return "NO_CARD_NAME", None

    collection_number = parse_collection_number(soup)
    rarity_code = parse_rarity_code(soup)
    super_type, sub_type = parse_card_types(page_text)
    illustrator = parse_illustrator(lines)
    image_url = parse_image_url(soup)

    return "OK", {
        "official_card_code": card_code,
        "product_name": product_name,
        "name": card_name,
        "collection_number": collection_number,
        "card_number": collection_number,
        "rarity_code": rarity_code,
        "language": DEFAULT_LANGUAGE,
        "super_type": super_type,
        "sub_type": sub_type,
        "illustrator": illustrator,
        "image_url": image_url,
        "official_url": detail_url,
    }


def fetch_and_save(card_code: str, products_columns: Set[str], cards_columns: Set[str]) -> str:
    try:
        status, incoming = parse_page(card_code)
        
        if status == "OK" and incoming:
            conn = db_pool.getconn()
            try:
                # 1. Product 통제 (Lock)
                with product_lock:
                    product, is_new = insert_product_if_missing(conn, incoming["product_name"], products_columns)
                    conn.commit()
                    if is_new:
                        with stats_lock: stats["product_backfilled"] += 1
                        print(f"[PRODUCT INSERT] {product['product_id']} | {product['name']}")
                
                incoming["product_id"] = product["product_id"]
                
                # 2. Card 저장
                existing_card = find_existing_card(conn, incoming)
                
                if not existing_card:
                    card_id = insert_card(conn, incoming, cards_columns)
                    with stats_lock: stats["inserted"] += 1
                    print(f"[CARD INSERT] {card_code} | {incoming['name']} | {incoming.get('rarity_code')}")
                else:
                    if needs_update(existing_card, incoming):
                        update_card(conn, existing_card["card_id"], incoming, cards_columns)
                        with stats_lock: stats["updated"] += 1
                        print(f"[CARD UPDATE] {card_code} | {incoming['name']}")
                    else:
                        with stats_lock: stats["skipped"] += 1
                        print(f"[CARD SKIP] {card_code} | {incoming['name']}")
                
                conn.commit()
            except Exception as e:
                conn.rollback()
                print(f"[DB ERROR] {card_code} - {e}")
                status = "ERROR"
            finally:
                db_pool.putconn(conn)
                
        else:
            with stats_lock:
                if status == "NOT_FOUND": stats["not_found"] += 1
                elif status == "NO_PRODUCT_NAME": stats["no_product_name"] += 1
                elif status == "NO_CARD_NAME": stats["no_card_name"] += 1

        return status
    except Exception as e:
        print(f"[ROW ERROR] {card_code} - {e}")
        return "ERROR"


# ============================================================
# Main Sync (Jump Search + Multithread)
# ============================================================

def sync_cards():
    global db_pool
    # 커넥션 풀 초기화
    db_pool = pool.ThreadedConnectionPool(1, MAX_WORKERS + 2, **DB_CONFIG)
    
    conn = db_pool.getconn()
    try:
        products_columns = get_products_table_columns(conn)
        cards_columns = get_cards_table_columns(conn)
    finally:
        db_pool.putconn(conn)

    print("=" * 100)
    print("🚀 [점프 탐색(Jump Search) & 멀티스레드 결합 크롤러 시작]")
    print(f" - MAX_WORKERS: {MAX_WORKERS}")
    print(" - 탐색 방식: N개씩 점프하며 찌르고, 발견 시 뒤로 돌아가 사이를 병렬로 메움(Backfill)")
    print("=" * 100)

    try:
        with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
            for prefix, start_num, pad in CARD_SERIES:
                print(f"\n[START SERIES] {prefix} -----------------------------")
                
                current_num = start_num
                void_distance = 0
                max_void_distance = 100000  # 10만 단위 갭까지 허용 (절대 놓침 방지용)
                
                # 병렬 환경을 위한 캐시
                known_results = {}
                
                # 이 내부 함수는 num을 전달받아 캐쉬를 확인하고 없으면 크롤링을 트리거합니다.
                def process_num(num: int) -> bool:
                    if num in known_results:
                        return known_results[num]
                    
                    num_str = str(num).zfill(pad) if pad > 0 else str(num)
                    code = f"{prefix}{num_str}"
                    status = fetch_and_save(code, products_columns, cards_columns)
                    
                    success = status not in ("NOT_FOUND", "NO_PRODUCT_NAME", "NO_CARD_NAME", "ERROR")
                    known_results[num] = success
                    return success

                while void_distance < max_void_distance:
                    # 💡 유저 핵심 아이디어: 누적 빈칸 거리가 5만 개 이하면 보수적(10단위), 넘어가면 성큼(100단위)
                    step = 10 if void_distance < 50000 else 100
                    
                    # 1. 찌르기 (Probe)
                    if process_num(current_num):
                        num_str = str(current_num).zfill(pad) if pad > 0 else str(current_num)
                        print(f"🎯 [JUMP HIT] {prefix}{num_str} 발견! 빈칸(Backfill) 병렬 수집 및 전진 탐색 시작...")
                        void_distance = 0
                        
                        # 2. 백필(Backfill) : 건너뛰었던 곳 병렬 동시 수집
                        if current_num > start_num:
                            backfill_start = max(start_num, current_num - step + 1)
                            backfill_end = current_num - 1
                            if backfill_end >= backfill_start:
                                nums_to_backfill = list(range(backfill_start, backfill_end + 1))
                                futures = [executor.submit(process_num, n) for n in nums_to_backfill]
                                for fut in futures: fut.result()
                        
                        # 3. 전진 수집 (Forward Scan)
                        current_num += 1
                        misses = 0
                        while misses < 4:  # 연속 4번 실패하면 뭉치가 끝났다고 판단
                            chunk = list(range(current_num, current_num + 4))
                            futures = [executor.submit(process_num, n) for n in chunk]
                            
                            for fut in futures:
                                success = fut.result()
                                if success:
                                    misses = 0
                                else:
                                    misses += 1
                                
                                current_num += 1
                                if misses >= 4:
                                    break
                        
                        # 순차가 종료되었으므로 점프 스텝만큼 다시 이동
                        current_num += step
                        
                    else:
                        void_distance += step
                        current_num += step

                print(f"[STOP SERIES] '{prefix}' 시리즈 마감 (최대 허용 빈 공간 도달)")

        print("\n" + "=" * 100)
        print(f"🎉 SYNC DONE | inserted={stats['inserted']}, updated={stats['updated']}, skipped={stats['skipped']}, "
              f"product_backfilled={stats['product_backfilled']}, not_found={stats['not_found']}, "
              f"no_product_name={stats['no_product_name']}, no_card_name={stats['no_card_name']}")
        print("=" * 100)

    finally:
        if db_pool:
            db_pool.closeall()


if __name__ == "__main__":
    sync_cards()