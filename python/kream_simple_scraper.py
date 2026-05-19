#!/usr/bin/env python3
"""
kream_simple_scraper.py — KREAM 비로그인 메인 가격 daily scraper.

[배경]
기존 kream_ditto.py는 playwright + chromium + CDP attach (sales 히스토리 수집).
prod docker에 chromium 없어서 21:45 cron 매일 silent fail.

이 스크립트는 단순 requests + meta tag 정규식.
chromium 불필요 → prod cron에서 동작.

[추출]
<meta property="product:price:amount" content="207000">

[validation]
- price > 0 and < 10억
- 전일 대비 ±70% 이내 (outlier 차단)
- fail 시 skip (DB 기존 데이터 유지)

[현재 mapping]
메타몽 1장. 추후 KREAM 콜라보/프로모 추가 시 dict 확장.

[사용]
  python python/kream_simple_scraper.py --dry-run
  python python/kream_simple_scraper.py --card-id CRD_205C20056CBF48F8B08D
  python python/kream_simple_scraper.py

[prod cron 통합]
PriceSyncScheduler에 새 @Scheduled cron 추가 (별도 작업).
"""

import argparse
import re
import sys
import time
import uuid
from datetime import datetime
from typing import Optional, Tuple

import psycopg2
import requests

from config import get_db_dsn


# 카드별 KREAM product_id mapping
# 추가 시: cardId + KREAM URL의 마지막 숫자
KREAM_PRODUCTS = {
    "CRD_205C20056CBF48F8B08D": "508949",  # 메타몽 (Pokemon TCG Ditto's Time Capsule Promo Card)
}

HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36",
    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8",
    "Accept-Language": "ko-KR,ko;q=0.9,en;q=0.8",
    "Accept-Encoding": "gzip, deflate, br",
    "Sec-Fetch-Dest": "document",
    "Sec-Fetch-Mode": "navigate",
    "Sec-Fetch-Site": "none",
    "Sec-Fetch-User": "?1",
    "Upgrade-Insecure-Requests": "1",
}

KREAM_URL = "https://kream.co.kr/products/{}"
PRICE_META_RE = re.compile(
    r'<meta\s+property="product:price:amount"\s+content="(\d+)"', re.IGNORECASE
)
SOURCE = "KREAM"


def fetch_kream_price(product_id: str) -> Optional[int]:
    """KREAM product page → main price. None = fail."""
    url = KREAM_URL.format(product_id)
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        if r.status_code != 200:
            print(f"  [WARN] {product_id} HTTP {r.status_code}")
            return None
        m = PRICE_META_RE.search(r.text)
        if not m:
            print(f"  [WARN] {product_id} meta tag 없음 (page 구조 변경 의심)")
            return None
        return int(m.group(1))
    except requests.RequestException as e:
        print(f"  [ERROR] {product_id} request fail: {type(e).__name__}: {e}")
        return None


def get_prev_kream_price(conn, card_id: str) -> Optional[int]:
    """가장 최근 KREAM price (validation 비교용)."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT price FROM price_snapshots "
            "WHERE card_id = %s AND source = %s "
            "ORDER BY traded_at DESC LIMIT 1",
            (card_id, SOURCE),
        )
        row = cur.fetchone()
        return row[0] if row else None


def validate(new_price: int, prev_price: Optional[int]) -> Tuple[bool, str]:
    """가격 sanity check. 사용자 요구 — 이상하면 skip."""
    if new_price <= 0:
        return False, "price<=0"
    if new_price > 1_000_000_000:  # 10억 초과
        return False, "price>1B"
    if prev_price is None or prev_price <= 0:
        return True, "first_or_no_prev"
    delta_pct = abs(new_price - prev_price) / prev_price
    if delta_pct > 0.70:
        return False, f"delta={delta_pct * 100:.0f}%>70%"
    return True, "ok"


def save_price(conn, card_id: str, price: int, observed_at: datetime) -> str:
    """price_snapshots INSERT (1일 1건, snapshot_id = unique)."""
    snapshot_id = f"kream_simple_{card_id}_{observed_at.strftime('%Y%m%d')}"
    with conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO price_snapshots
                (price_snapshot_id, card_id, source, price, card_status,
                 traded_at, collected_at, raw_price, raw_currency, validation_status)
            VALUES (%s, %s, %s, %s, 'RAW', %s, %s, %s, 'KRW', 'VALID')
            ON CONFLICT (price_snapshot_id) DO UPDATE SET
                price = EXCLUDED.price,
                collected_at = EXCLUDED.collected_at,
                raw_price = EXCLUDED.raw_price
            """,
            (snapshot_id, card_id, SOURCE, price, observed_at, observed_at, price),
        )
    conn.commit()
    return snapshot_id


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="DB 저장 X, 계획만")
    parser.add_argument("--card-id", help="특정 cardId만 (default: 전체)")
    parser.add_argument("--sleep", type=float, default=2.0, help="요청 간격 초 (default 2.0)")
    args = parser.parse_args()

    products = KREAM_PRODUCTS
    if args.card_id:
        products = {k: v for k, v in products.items() if k == args.card_id}
    if not products:
        print("no products matched")
        sys.exit(1)

    mode = "DRY-RUN" if args.dry_run else "REAL"
    print(f"=== KREAM simple scraper ({mode}) ===")
    print(f"targets: {len(products)}")
    print()

    try:
        conn = psycopg2.connect(get_db_dsn())
    except Exception as e:
        print(f"DB connect fail: {e}")
        sys.exit(2)

    now = datetime.now()
    ok = skipped = failed = 0

    for card_id, product_id in products.items():
        print(f"[{card_id}] kream product {product_id}")
        new_price = fetch_kream_price(product_id)
        if new_price is None:
            failed += 1
            continue

        prev = get_prev_kream_price(conn, card_id)
        valid, reason = validate(new_price, prev)
        prev_str = f"{prev:,}" if prev else "None"
        print(f"  price={new_price:,} prev={prev_str} validate={reason}")

        if not valid:
            print(f"  [SKIP] validation fail")
            skipped += 1
            continue

        if args.dry_run:
            print(f"  [DRY] would insert {new_price:,}")
        else:
            sid = save_price(conn, card_id, new_price, now)
            print(f"  [SAVED] snapshot_id={sid}")
        ok += 1
        time.sleep(args.sleep)

    conn.close()
    print()
    print(f"=== 완료: ok={ok}, skip={skipped}, fail={failed} ===")


if __name__ == "__main__":
    main()
