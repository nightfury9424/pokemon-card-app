#!/usr/bin/env python3
"""KREAM 메타몽 Pokemon Town 2025 프로모 — sales endpoint 기반 incremental 적층.

운영 모델:
- Chrome 인스턴스(`--remote-debugging-port=9222 --user-data-dir=/tmp/chrome_kream_profile`)가 떠있고
  KREAM 로그인 + 도메인 페이지가 열려 있어야 함.
- 매일 cron이 CDP attach → 페이지의 useNuxtApp().$axios로 sales API 페이징 호출.

수집 룰:
- `/api/p/products/<id>/sales?cursor=N&per_page=50` — 거래 row 시계열 (체결가 + UTC 시각 + 옵션).
- DB의 직전 MAX(traded_at) 이후 row만 INSERT (incremental).
- 5등급만: Ungraded / PSA 10 / PSA 9 / BRG 10 / BRG 9 (영문·한글 합침).
- 그 외 (PSA 8, BRG 8.5/8 등): skip.
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
import uuid
from dotenv import load_dotenv
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

from config import get_db_dsn  # Phase 1-4: env 기반 DSN
DB_DSN = get_db_dsn()
CDP_URL = "http://localhost:9222"

CARD_ID = "CRD_205C20056CBF48F8B08D"
PRODUCT_ID = 508949
SOURCE = "KREAM"
PER_PAGE = 50

# KREAM `option` 문자열 → (grading_company, grade_value, card_status, title).
# 5등급만 적층 — 나머지 등급은 응답에 와도 skip.
OPTION_MAP: dict[str, tuple[str | None, str | None, str, str]] = {
    "Ungraded":     (None,  None, "RAW",    "Ungraded"),
    "PSA 10":       ("PSA", "10", "GRADED", "PSA 10"),
    "PSA 9":        ("PSA", "9",  "GRADED", "PSA 9"),
    # BRG 영문·한글은 합쳐서 BRG 10 / BRG 9 로 통합 (title만 원본 보존).
    "BRG 10 영문":  ("BRG", "10", "GRADED", "BRG 10 영문"),
    "BRG 10 한글":  ("BRG", "10", "GRADED", "BRG 10 한글"),
    "BRG 9 영문":   ("BRG", "9",  "GRADED", "BRG 9 영문"),
    "BRG 9 한글":   ("BRG", "9",  "GRADED", "BRG 9 한글"),
}


async def fetch_sales_after(after_utc: datetime | None) -> list[dict]:
    """sales 페이징 호출. `after_utc` 이후 거래만 반환 (포함 X). 최신부터 정렬되므로
    한 페이지 안에 cutoff 만나면 break."""
    collected: list[dict] = []
    cursor = 1
    async with async_playwright() as pw:
        try:
            browser = await pw.chromium.connect_over_cdp(CDP_URL, timeout=5000)
        except Exception as exc:
            log.error("CDP attach 실패 (%s). Chrome 9222 떠있어야 함.", exc)
            raise SystemExit(2)
        target = None
        for ctx in browser.contexts:
            for p in ctx.pages:
                if "kream.co.kr" in p.url:
                    target = p
                    break
            if target:
                break
        if not target:
            log.error("KREAM 페이지 열려있지 않음")
            raise SystemExit(3)
        log.info("[CDP] attached. page: %s", target.url)

        while True:
            data = await target.evaluate(f"""async (cursor) => {{
                const app = useNuxtApp();
                return await app.$axios.$get(
                    'https://api.kream.co.kr/api/p/products/{PRODUCT_ID}/sales',
                    {{ params: {{ cursor: cursor, per_page: {PER_PAGE}, request_key: crypto.randomUUID() }} }}
                );
            }}""", cursor)
            items = (data.get("items") or [])
            if not items:
                break
            stop = False
            for it in items:
                dc = it.get("date_created")
                if not dc:
                    continue
                try:
                    ts = datetime.fromisoformat(dc.replace("Z", "+00:00"))
                except ValueError:
                    continue
                if after_utc is not None and ts <= after_utc:
                    stop = True
                    break  # 최신부터 정렬되어 있으니 이후 모두 더 옛날
                collected.append(it)
            if stop:
                break
            nxt = data.get("next_cursor")
            if not nxt or nxt == cursor:
                break
            cursor = nxt
        return collected


def get_last_traded_at(conn) -> datetime | None:
    with conn.cursor() as cur:
        cur.execute(
            "SELECT MAX(traded_at) FROM price_snapshots WHERE card_id=%s AND source=%s",
            (CARD_ID, SOURCE),
        )
        row = cur.fetchone()
    if not row or row[0] is None:
        return None
    # DB는 naive timestamp (KST 기준 또는 UTC?). 우리 기존 코드들이 naive를 KST로 박았음.
    # incremental cutoff은 UTC로 비교해야 정확 — DB 값을 UTC tz-aware로 해석.
    # 다만 기존 KREAM raw rows는 KST datetime을 naive로 박혔으니 약간 부정확.
    # 가장 안전: DB값을 KST로 보고 UTC로 변환.
    from datetime import timedelta
    return row[0].replace(tzinfo=timezone(timedelta(hours=9))).astimezone(timezone.utc)


def insert_sale(cur, sale: dict) -> bool:
    """sale row INSERT. 매핑 외 옵션이면 False (skip)."""
    opt_label = sale.get("option") or ""
    meta = OPTION_MAP.get(opt_label)
    if not meta:
        return False
    company, grade, status, title = meta
    price = int(sale["price"])
    ts_utc = datetime.fromisoformat(sale["date_created"].replace("Z", "+00:00"))
    # DB는 naive timestamp 컨벤션 — KST naive로 저장 (기존 코드 패턴과 일관).
    from datetime import timedelta
    ts_kst_naive = ts_utc.astimezone(timezone(timedelta(hours=9))).replace(tzinfo=None)
    sid = "SNAP_" + uuid.uuid4().hex.upper()[:20]
    cur.execute(
        """
        INSERT INTO price_snapshots
            (price_snapshot_id, card_id, source, price,
             card_status, grading_company, grade_value, title,
             traded_at, collected_at, created_at,
             raw_price, raw_currency)
        VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, NOW(), NOW(), %s, 'KRW')
        """,
        (sid, CARD_ID, SOURCE, price,
         status, company, grade, title,
         ts_kst_naive, price),
    )
    return True


def main() -> None:
    conn = psycopg2.connect(DB_DSN)
    try:
        after_utc = get_last_traded_at(conn)
        log.info("[Incremental] DB 마지막 traded_at (UTC): %s", after_utc)
        sales = asyncio.run(fetch_sales_after(after_utc))
        log.info("[Fetch] 신규 후보: %d건", len(sales))
        if not sales:
            log.info("적층할 신규 거래 없음")
            return
        # 최신 → 옛날 순으로 왔으니 옛날 → 최신 순으로 INSERT (자연스러운 시계열)
        sales.reverse()
        with conn.cursor() as cur:
            saved = 0
            skipped = 0
            for s in sales:
                if insert_sale(cur, s):
                    saved += 1
                else:
                    skipped += 1
        conn.commit()
        log.info("완료: %d건 적층, %d건 옵션 매핑 외 skip", saved, skipped)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
