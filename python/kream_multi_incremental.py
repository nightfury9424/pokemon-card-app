#!/usr/bin/env python3
"""KREAM 멀티카드 증분 시세 수집 — CDP(로그인 Chrome 9222) 페이징 → prod ingest push.

kream_agent.py(페이지 크롤, 최근 ~20건)로는 잉어킹처럼 거래량 많은 카드에서 유실이 나서,
sales API 페이징(로그인 Chrome의 $axios) 방식으로 최근 OVERLAP_DAYS 치를 전부 긁어 push한다.
서버 ingest 가 카드별 MAX(traded_at) 이후만 INSERT (멱등) — 중복 push 무해.

전제 (KREAM.md 'Chrome 인스턴스' 절):
  /Applications/Google Chrome.app/.../Google Chrome \
    --remote-debugging-port=9222 --user-data-dir=/tmp/chrome_kream_profile
  + KREAM 로그인 1회 + kream.co.kr 페이지 1개 열어두기 (닫히면 수집 실패)

실행: KREAM_AGENT_TOKEN=<prod와 동일> .venv_kream/bin/python kream_multi_incremental.py
launchd: com.pokefolio.kream-multi.plist (매일 22:30)
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from dotenv import load_dotenv
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

CDP_URL = "http://localhost:9222"
API = os.environ.get("POKEFOLIO_API", "https://52.78.3.120.nip.io").rstrip("/")
TOKEN = os.environ.get("KREAM_AGENT_TOKEN", "")
PER_PAGE = 50
OVERLAP_DAYS = int(os.environ.get("KREAM_OVERLAP_DAYS", "3"))  # 이 기간치 재전송(서버 멱등)

# (card_id, kream_product_id) — 새 KREAM 카드 추가 시 여기에만 추가
TARGETS: list[tuple[str, int]] = [
    ("CRD_205C20056CBF48F8B08D", 508949),   # 메타몽 Pokemon Town 2025
    ("CRD_D487A25786354189AF25", 893073),   # 잉어킹 메가 페스타 2026
]

# KREAM option → (grading_company, grade_value, card_status, title). 5등급 외 skip.
OPTION_MAP: dict[str, tuple[str | None, str | None, str, str]] = {
    "Ungraded":     (None,  None, "RAW",    "Ungraded"),
    "PSA 10":       ("PSA", "10", "GRADED", "PSA 10"),
    "PSA 9":        ("PSA", "9",  "GRADED", "PSA 9"),
    "BRG 10 영문":  ("BRG", "10", "GRADED", "BRG 10 영문"),
    "BRG 10 한글":  ("BRG", "10", "GRADED", "BRG 10 한글"),
    "BRG 9 영문":   ("BRG", "9",  "GRADED", "BRG 9 영문"),
    "BRG 9 한글":   ("BRG", "9",  "GRADED", "BRG 9 한글"),
}

KST = timezone(timedelta(hours=9))


async def fetch_recent(page, product_id: int, cutoff_utc: datetime) -> list[dict]:
    """sales 페이징 (최신부터). cutoff_utc 이전 거래 만나면 중단."""
    out: list[dict] = []
    cursor = 1
    while True:
        data = await page.evaluate(f"""async (cursor) => {{
            const app = useNuxtApp();
            return await app.$axios.$get(
                'https://api.kream.co.kr/api/p/products/{product_id}/sales',
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
            if ts <= cutoff_utc:
                stop = True
                break
            out.append(it)
        if stop:
            break
        nxt = data.get("next_cursor")
        if not nxt or nxt == cursor:
            break
        cursor = nxt
    return out


def to_sale(card_id: str, it: dict) -> dict | None:
    meta = OPTION_MAP.get(it.get("option") or "")
    if not meta:
        return None
    company, grade, status, title = meta
    ts_kst = datetime.fromisoformat(it["date_created"].replace("Z", "+00:00")).astimezone(KST).replace(tzinfo=None)
    return {
        "cardId": card_id,
        "cardStatus": status,
        "gradingCompany": company,
        "gradeValue": grade,
        "title": title,
        "price": int(it["price"]),
        "tradedAt": ts_kst.isoformat(),
    }


def post_ingest(sales: list[dict]) -> dict:
    from curl_cffi import requests as cffi
    r = cffi.post(f"{API}/api/kream-agent/ingest",
                  headers={"X-Kream-Agent-Token": TOKEN, "Content-Type": "application/json"},
                  json={"sales": sales}, timeout=60, verify=False)
    r.raise_for_status()
    return r.json()


async def main() -> None:
    if not TOKEN:
        log.error("KREAM_AGENT_TOKEN 없음 (.env 또는 env)")
        raise SystemExit(1)
    cutoff = datetime.now(timezone.utc) - timedelta(days=OVERLAP_DAYS)
    async with async_playwright() as pw:
        try:
            browser = await pw.chromium.connect_over_cdp(CDP_URL, timeout=5000)
        except Exception as exc:
            log.error("CDP attach 실패 (%s) — Chrome 9222 + KREAM 로그인 필요", exc)
            raise SystemExit(2)
        page = None
        for ctx in browser.contexts:
            for p in ctx.pages:
                if "kream.co.kr" in p.url:
                    page = p
                    break
            if page:
                break
        if not page:
            log.error("KREAM 페이지 없음")
            raise SystemExit(3)
        log.info("[CDP] attached: %s", page.url)

        all_sales: list[dict] = []
        for card_id, product_id in TARGETS:
            items = await fetch_recent(page, product_id, cutoff)
            sales = [s for s in (to_sale(card_id, it) for it in items) if s]
            log.info("%s (product %s): 최근 %d일 %d건", card_id, product_id, OVERLAP_DAYS, len(sales))
            all_sales.extend(sales)

    if not all_sales:
        log.info("전송할 체결 없음")
        return
    res = post_ingest(all_sales)
    log.info("ingest 응답: %s (전송 %d건 — 서버가 신규만 INSERT)", res, len(all_sales))


if __name__ == "__main__":
    asyncio.run(main())
