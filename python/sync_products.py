import re
import time
import uuid
from typing import List, Dict, Optional, Tuple
from urllib.parse import urljoin

import psycopg2
import psycopg2.extras
import requests
from bs4 import BeautifulSoup, Tag

# ============================================================
# 설정
# ============================================================

BASE_URL = "https://pokemoncard.co.kr"

# info1만 사용
CATEGORY_URLS: List[Tuple[str, str]] = [
    ("EXPANSION", "https://pokemoncard.co.kr/card/category/info1"),
]

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

DEFAULT_LANGUAGE = "KO"


# ============================================================
# 유틸
# ============================================================

def clean_text(text: Optional[str]) -> str:
    if not text:
        return ""
    return re.sub(r"\s+", " ", text).strip()


def fetch_html(url: str, timeout: int = 15) -> str:
    response = requests.get(url, headers=HEADERS, timeout=timeout)
    response.raise_for_status()
    return response.text


def generate_product_id() -> str:
    return f"PRD_{uuid.uuid4().hex[:20].upper()}"


def parse_product_type(name: str) -> str:
    if "하이클래스팩" in name:
        return "HIGH_CLASS_PACK"
    if "강화 확장팩" in name:
        return "ENHANCED_BOOSTER"
    if "확장팩" in name:
        return "BOOSTER"
    return "SPECIAL"


def parse_series_name(name: str) -> str:
    pattern = r"^(.*?)\s+(확장팩|강화 확장팩|하이클래스팩)"
    match = re.match(pattern, name)
    if match:
        return clean_text(match.group(1))
    return ""


# ============================================================
# 목록 페이지 파싱
# ============================================================

def extract_product_name(tag: Tag) -> str:
    h4 = tag.find("h4")
    if h4:
        return clean_text(h4.get_text(" ", strip=True))
    return ""


def extract_image_url(tag: Tag) -> str:
    img = tag.find("img")
    if img and img.get("src"):
        return urljoin(BASE_URL, img["src"])
    return ""


def build_product_row_from_list(category_type: str, tag: Tag) -> Optional[Dict[str, str]]:
    name = extract_product_name(tag)
    if not name:
        return None

    return {
        "name": name,
        "series_name": parse_series_name(name),
        "product_type": parse_product_type(name),
        "language": DEFAULT_LANGUAGE,
        "image_url": extract_image_url(tag),
        "category_type": category_type,
    }


def scrape_products_from_category(category_type: str, url: str) -> List[Dict[str, str]]:
    html = fetch_html(url)
    soup = BeautifulSoup(html, "html.parser")

    rows: List[Dict[str, str]] = []
    seen_names = set()

    candidates = soup.find_all(lambda t: t.name in ["div", "li", "section"] and t.find("h4"))

    for tag in candidates:
        row = build_product_row_from_list(category_type, tag)
        if not row:
            continue

        if row["name"] in seen_names:
            continue

        if len(row["name"]) < 2:
            continue

        seen_names.add(row["name"])
        rows.append(row)

    return rows


def scrape_all_products() -> List[Dict[str, str]]:
    all_rows: List[Dict[str, str]] = []

    for category_type, url in CATEGORY_URLS:
        try:
            rows = scrape_products_from_category(category_type, url)
            print(f"[SCRAPE] {category_type}: {len(rows)}건")
            all_rows.extend(rows)
        except Exception as e:
            print(f"[ERROR] scrape failed - {category_type} - {e}")

        time.sleep(1.0)

    return all_rows


# ============================================================
# DB 처리
# ============================================================

def get_connection():
    return psycopg2.connect(**DB_CONFIG)


def find_existing_product(conn, name: str, language: str) -> Optional[Dict]:
    with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
        cur.execute(
            """
            SELECT *
            FROM products
            WHERE name = %s
              AND language = %s
            LIMIT 1
            """,
            (name, language)
        )
        return cur.fetchone()


def insert_product(conn, row: Dict[str, str]) -> str:
    product_id = generate_product_id()

    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO products (
                product_id,
                name,
                series_name,
                product_type,
                language,
                image_url,
                created_at,
                updated_at
            ) VALUES (
                %s, %s, %s, %s, %s, %s, NOW(), NOW()
            )
            """,
            (
                product_id,
                row["name"],
                row.get("series_name"),
                row.get("product_type"),
                row["language"],
                row.get("image_url"),
            )
        )

    return product_id


def needs_update(existing: Dict, incoming: Dict) -> bool:
    compare_pairs = [
        ("series_name", "series_name"),
        ("product_type", "product_type"),
        ("image_url", "image_url"),
    ]

    for existing_key, incoming_key in compare_pairs:
        old_val = clean_text(str(existing.get(existing_key) or ""))
        new_val = clean_text(str(incoming.get(incoming_key) or ""))
        if old_val != new_val:
            return True

    return False


def update_product(conn, product_id: str, row: Dict[str, str]) -> None:
    with conn.cursor() as cur:
        cur.execute(
            """
            UPDATE products
               SET series_name = %s,
                   product_type = %s,
                   image_url = %s,
                   updated_at = NOW()
             WHERE product_id = %s
            """,
            (
                row.get("series_name"),
                row.get("product_type"),
                row.get("image_url"),
                product_id,
            )
        )


def sync_products(rows: List[Dict[str, str]]) -> None:
    inserted = 0
    updated = 0
    skipped = 0

    conn = get_connection()
    conn.autocommit = False

    try:
        for row in rows:
            try:
                existing = find_existing_product(
                    conn=conn,
                    name=row["name"],
                    language=row["language"],
                )

                if not existing:
                    product_id = insert_product(conn, row)
                    inserted += 1
                    print(f"[INSERT] {product_id} | {row['name']}")
                else:
                    if needs_update(existing, row):
                        update_product(conn, existing["product_id"], row)
                        updated += 1
                        print(f"[UPDATE] {existing['product_id']} | {row['name']}")
                    else:
                        skipped += 1
                        print(f"[SKIP]   {existing['product_id']} | {row['name']}")

                conn.commit()

            except Exception as e:
                conn.rollback()
                print(f"[ROW ERROR] {row.get('name')} - {e}")

        print("=" * 60)
        print(f"SYNC DONE | inserted={inserted}, updated={updated}, skipped={skipped}")
        print("=" * 60)

    finally:
        conn.close()


# ============================================================
# 실행
# ============================================================

def main():
    rows = scrape_all_products()
    print(f"[TOTAL SCRAPED] {len(rows)}건")
    sync_products(rows)


if __name__ == "__main__":
    main()