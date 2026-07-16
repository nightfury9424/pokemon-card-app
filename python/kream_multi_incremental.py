#!/usr/bin/env python3
"""KREAM 멀티카드 시세 무인 수집 — 비로그인 curl_cffi 크롤 → prod ingest push.

메타몽 agent(kream_agent.py)와 같은 무인 모델: Chrome/로그인/CDP 전부 불필요.
상품 페이지의 __NUXT_DATA__(Nuxt 인덱스 참조 직렬화)에서 최근 체결 ~10건을 파싱해 push.
서버 ingest 가 카드별 MAX(traded_at) 이후만 INSERT (멱등) — 중복 push 무해.

잉어킹은 일 200건+ 거래라 15분 간격 실행으로 유실 방지 (launchd com.pokefolio.kream-multi,
StartInterval 900). 창·로그인 유지 조건 없음. ※대량 과거 이력 백필만 별도 CDP 방식.

실행: KREAM_AGENT_TOKEN=<prod와 동일> .venv_kream/bin/python kream_multi_incremental.py
"""
from __future__ import annotations

import json
import logging
import os
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from curl_cffi import requests as cffi

ROOT = Path(__file__).resolve().parent
try:
    from dotenv import load_dotenv
    load_dotenv(ROOT / ".env")
except ImportError:
    pass

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

API = os.environ.get("POKEFOLIO_API", "https://52.78.3.120.nip.io").rstrip("/")
TOKEN = os.environ.get("KREAM_AGENT_TOKEN", "")

# (card_id, kream_product_id) — 새 KREAM 카드 추가 시 여기에만 추가
TARGETS: list[tuple[str, int]] = [
    ("CRD_205C20056CBF48F8B08D", 508949),   # 메타몽 Pokemon Town 2025
    ("CRD_D487A25786354189AF25", 893073),   # 잉어킹 메가 페스타 2026
]

# 정규화된 option → (grading_company, grade_value, card_status, title). 5등급 외 skip.
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
NUXT_RE = re.compile(r'<script type="application/json"[^>]*id="__NUXT_DATA__"[^>]*>(.*?)</script>', re.S)


def normalize_option(opt: str) -> str:
    """'PSA 10 (Card Ver.)' → 'PSA 10' 등 표기 정규화."""
    return re.sub(r"\s*\(Card Ver\.\)\s*", "", opt or "").strip()


def fetch_page_sales(product_id: int) -> list[tuple[str, int, str]]:
    """상품 페이지 __NUXT_DATA__에서 (option, price, date_created UTC) 최근 체결 추출."""
    r = cffi.get(f"https://kream.co.kr/products/{product_id}",
                 impersonate="chrome", timeout=25)
    r.raise_for_status()
    m = NUXT_RE.search(r.text)
    if not m:
        raise RuntimeError(f"product {product_id}: __NUXT_DATA__ 없음 (구조 변경?)")
    arr = json.loads(m.group(1))

    def deref(v):
        return arr[v] if isinstance(v, int) and 0 <= v < len(arr) else v

    out: list[tuple[str, int, str]] = []
    for el in arr:
        if isinstance(el, dict) and "date_created" in el and "price" in el and "product_option" in el:
            price = deref(el["price"])
            dc = deref(el["date_created"])
            opt_o = deref(el["product_option"])
            opt = deref(opt_o.get("name_display")) if isinstance(opt_o, dict) else opt_o
            if isinstance(price, int) and isinstance(dc, str):
                out.append((str(opt), price, dc))
    return out


def to_sale(card_id: str, opt: str, price: int, dc: str) -> dict | None:
    meta = OPTION_MAP.get(normalize_option(opt))
    if not meta:
        return None
    company, grade, status, title = meta
    ts_kst = datetime.fromisoformat(dc.replace("Z", "+00:00")).astimezone(KST).replace(tzinfo=None)
    return {
        "cardId": card_id,
        "cardStatus": status,
        "gradingCompany": company,
        "gradeValue": grade,
        "title": title,
        "price": price,
        "tradedAt": ts_kst.isoformat(),
    }


def post_ingest(sales: list[dict]) -> dict:
    r = cffi.post(f"{API}/api/kream-agent/ingest",
                  headers={"X-Kream-Agent-Token": TOKEN, "Content-Type": "application/json"},
                  json={"sales": sales}, timeout=60, verify=False)
    r.raise_for_status()
    return r.json()


def main() -> None:
    if not TOKEN:
        log.error("KREAM_AGENT_TOKEN 없음 (.env 또는 launchd env)")
        raise SystemExit(1)
    all_sales: list[dict] = []
    errors = []
    for card_id, product_id in TARGETS:
        try:
            rows = fetch_page_sales(product_id)
            sales = [s for s in (to_sale(card_id, *row) for row in rows) if s]
            log.info("%s (product %s): 페이지 체결 %d건", card_id, product_id, len(sales))
            all_sales.extend(sales)
        except Exception as exc:
            errors.append(f"{product_id}: {exc}")
            log.error("product %s 크롤 실패: %s", product_id, exc)
    if not all_sales:
        if errors:
            raise SystemExit(4)
        log.info("전송할 체결 없음")
        return
    res = post_ingest(all_sales)
    log.info("ingest 응답: %s (전송 %d건 — 서버가 카드별 신규만 INSERT)", res, len(all_sales))


if __name__ == "__main__":
    main()
