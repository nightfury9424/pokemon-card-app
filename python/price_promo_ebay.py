#!/usr/bin/env python3
from __future__ import annotations

"""
ko_promo_price_scraper.py - eBay API 기반 한국 독점 프로모 카드 가격 수집
대상: 메타몽 PR (Pokemon Town 2025, CRD_205C20056CBF48F8B08D)

우선순위:
1. eBay Finding API findCompletedItems 판매 완료 가격
2. Marketplace Insights item_sales/search 판매 데이터
3. Browse API sold 관련 필터 조합 테스트 결과
4. 체결가가 없으면 Browse API active listing 중앙값 fallback
"""

import base64
import logging
import os
import statistics
import time
import uuid
from datetime import datetime, timezone
from typing import Any, Optional

import psycopg2
import requests

logging.basicConfig(level=logging.INFO, format="[%(levelname)s] %(message)s")
log = logging.getLogger(__name__)

from config import get_db_dsn  # Phase 1-4: env 기반 DSN
DB_DSN = get_db_dsn()
CARD_ID = "CRD_205C20056CBF48F8B08D"
CARD_NAME = "메타몽 (Pokemon Town 2025 프로모)"

EBAY_APP_ID = os.getenv("EBAY_APP_ID", "")
EBAY_CERT_ID = os.getenv("EBAY_CERT_ID", "")
EBAY_DEV_ID = os.getenv("EBAY_DEV_ID", "")

MARKETPLACE_ID = "EBAY_US"
USD_TO_KRW_FALLBACK = 1380.0

SEARCH_QUERIES = [
    "Ditto pokemon town 2025 promo",
    "メタモン ポケモンタウン 2025",
]

REQUEST_TIMEOUT = 25


def request_json(
    method: str,
    url: str,
    *,
    headers: Optional[dict[str, str]] = None,
    params: Optional[dict[str, str]] = None,
    data: Optional[dict[str, str]] = None,
    retries: int = 0,
    backoff_base: float = 1.5,
) -> tuple[int, dict[str, Any] | list[Any] | None, str]:
    """JSON API 호출. 500/429는 exponential backoff로 재시도한다."""
    last_status = 0
    last_text = ""

    for attempt in range(retries + 1):
        try:
            resp = requests.request(
                method,
                url,
                headers=headers,
                params=params,
                data=data,
                timeout=REQUEST_TIMEOUT,
            )
            last_status = resp.status_code
            last_text = resp.text

            if resp.status_code not in (429, 500, 502, 503, 504):
                try:
                    return resp.status_code, resp.json(), resp.text
                except ValueError:
                    return resp.status_code, None, resp.text

            if attempt < retries:
                sleep_s = backoff_base * (2**attempt)
                log.warning(
                    "재시도 대상 응답: HTTP %s, %.1f초 대기 후 재시도 (%s/%s)",
                    resp.status_code,
                    sleep_s,
                    attempt + 1,
                    retries,
                )
                time.sleep(sleep_s)
        except requests.RequestException as exc:
            last_text = str(exc)
            if attempt < retries:
                sleep_s = backoff_base * (2**attempt)
                log.warning("요청 예외: %s, %.1f초 대기 후 재시도", exc, sleep_s)
                time.sleep(sleep_s)
            else:
                return 0, None, str(exc)

    try:
        parsed = requests.models.complexjson.loads(last_text)
    except Exception:
        parsed = None
    return last_status, parsed, last_text


def summarize_error(payload: Any, raw_text: str) -> str:
    if isinstance(payload, dict):
        for key in ("errors", "errorMessage", "error", "message"):
            if key in payload:
                return str(payload[key])[:700]
    return raw_text[:700].replace("\n", " ")


def get_oauth_token(scopes: list[str]) -> Optional[str]:
    creds = base64.b64encode(f"{EBAY_APP_ID}:{EBAY_CERT_ID}".encode()).decode()
    status, payload, raw = request_json(
        "POST",
        "https://api.ebay.com/identity/v1/oauth2/token",
        headers={
            "Authorization": f"Basic {creds}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
        data={"grant_type": "client_credentials", "scope": " ".join(scopes)},
        retries=2,
    )
    if status == 200 and isinstance(payload, dict) and payload.get("access_token"):
        log.info("OAuth 토큰 발급 성공: scopes=%s", ", ".join(scopes))
        return str(payload["access_token"])

    log.warning(
        "OAuth 토큰 발급 실패: HTTP %s | %s",
        status,
        summarize_error(payload, raw),
    )
    return None


def get_usd_to_krw() -> float:
    status, payload, raw = request_json(
        "GET", "https://api.exchangerate-api.com/v4/latest/USD", retries=1
    )
    if status == 200 and isinstance(payload, dict):
        try:
            rate = float(payload["rates"]["KRW"])
            log.info("USD/KRW 환율 조회 성공: %.2f", rate)
            return rate
        except (KeyError, TypeError, ValueError):
            pass
    log.warning("환율 조회 실패 -> %.0f 사용 | %s", USD_TO_KRW_FALLBACK, raw[:200])
    return USD_TO_KRW_FALLBACK


def title_matches(title: str) -> bool:
    text = title.lower()
    has_ditto = "ditto" in text or "メタモン" in title or "메타몽" in title
    has_town = (
        "pokemon town" in text
        or "pokémon town" in text
        or "ポケモンタウン" in title
        or "포켓몬타운" in title
        or "포켓몬 타운" in title
    )
    has_2025 = "2025" in text
    return has_ditto and has_town and has_2025


# title에서 등급 추출. (grading_company, grade_value) 또는 (None, None)=RAW.
# 보수적으로: 명확한 등급 표기만 인정. 모호하면 None (= RAW로 안 박고 skip 가능).
import re as _re
_GRADE_PATTERNS = [
    # PSA 10 / PSA10 / PSA Gem Mint 10
    (_re.compile(r"\bpsa\s*(?:gem\s*mint\s*)?(\d+(?:\.\d)?)\b", _re.IGNORECASE), "PSA"),
    # BGS 9.5 / BGS 10
    (_re.compile(r"\bbgs\s*(\d+(?:\.\d)?)\b", _re.IGNORECASE), "BGS"),
    # CGC 10 / CGC 9.5
    (_re.compile(r"\bcgc\s*(?:gem\s*mint\s*|pristine\s*)?(\d+(?:\.\d)?)\b", _re.IGNORECASE), "CGC"),
    # SGC 10
    (_re.compile(r"\bsgc\s*(\d+(?:\.\d)?)\b", _re.IGNORECASE), "SGC"),
    # BRG 10 (한국 등급사)
    (_re.compile(r"\bbrg\s*(\d+(?:\.\d)?)\b", _re.IGNORECASE), "BRG"),
]


def extract_grade_from_title(title: str) -> tuple[Optional[str], Optional[str]]:
    """title에서 등급 추출. 매칭 없으면 (None, None) = Ungraded."""
    for pattern, company in _GRADE_PATTERNS:
        m = pattern.search(title)
        if m:
            return company, m.group(1)
    return None, None


def usd_to_price_item(
    usd: float,
    usd_to_krw: float,
    *,
    title: str,
    source_detail: str,
    traded_at: Optional[datetime] = None,
    url: str = "",
) -> dict[str, Any]:
    company, grade = extract_grade_from_title(title)
    return {
        "price": int(round(usd * usd_to_krw)),
        "usd": usd,
        "title": title,
        "source_detail": source_detail,
        "traded_at": traded_at or datetime.now(timezone.utc),
        "url": url,
        "grading_company": company,
        "grade_value": grade,
        "card_status": "GRADED" if company else "RAW",
    }


def parse_amount(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).replace(",", "").replace("$", "").replace("US", "").strip()
    try:
        return float(text)
    except ValueError:
        return None


def extract_browse_items(payload: Any, usd_to_krw: float, source_detail: str) -> list[dict[str, Any]]:
    if not isinstance(payload, dict):
        return []
    out: list[dict[str, Any]] = []
    for item in payload.get("itemSummaries", []) or []:
        title = str(item.get("title") or "")
        if not title_matches(title):
            continue
        price_obj = item.get("price") or {}
        if price_obj.get("currency") not in (None, "USD"):
            continue
        usd = parse_amount(price_obj.get("value"))
        if usd is None or usd < 5 or usd > 5000:
            continue
        out.append(
            usd_to_price_item(
                usd,
                usd_to_krw,
                title=title,
                source_detail=source_detail,
                url=str(item.get("itemWebUrl") or item.get("itemAffiliateWebUrl") or ""),
            )
        )
    return out


def fetch_browse_active(token: str, usd_to_krw: float) -> list[dict[str, Any]]:
    url = "https://api.ebay.com/buy/browse/v1/item_summary/search"
    headers = {
        "Authorization": f"Bearer {token}",
        "X-EBAY-C-MARKETPLACE-ID": MARKETPLACE_ID,
    }
    filters = [
        "buyingOptions:{FIXED_PRICE|AUCTION},conditions:{USED|LIKE_NEW}",
        "buyingOptions:{FIXED_PRICE|AUCTION},priceCurrency:USD",
        "buyingOptions:{FIXED_PRICE|AUCTION}",
    ]
    collected: list[dict[str, Any]] = []
    seen_urls: set[str] = set()

    for query in SEARCH_QUERIES:
        for filter_value in filters:
            status, payload, raw = request_json(
                "GET",
                url,
                headers=headers,
                params={"q": query, "filter": filter_value, "limit": "50"},
                retries=1,
            )
            total = payload.get("total") if isinstance(payload, dict) else "?"
            if status == 200:
                log.info(
                    "Browse active 성공: q=%r filter=%r total=%s",
                    query,
                    filter_value,
                    total,
                )
                for item in extract_browse_items(payload, usd_to_krw, "browse_active"):
                    key = item["url"] or f"{item['title']}:{item['usd']}"
                    if key not in seen_urls:
                        seen_urls.add(key)
                        collected.append(item)
            else:
                log.warning(
                    "Browse active 실패: HTTP %s q=%r filter=%r | %s",
                    status,
                    query,
                    filter_value,
                    summarize_error(payload, raw),
                )
    return collected


def fetch_browse_sold_filter_tests(token: str, usd_to_krw: float) -> None:
    """Browse API는 공식적으로 completed/sold 검색 API가 아니므로 가능한 조합을 검증한다."""
    url = "https://api.ebay.com/buy/browse/v1/item_summary/search"
    headers = {
        "Authorization": f"Bearer {token}",
        "X-EBAY-C-MARKETPLACE-ID": MARKETPLACE_ID,
    }
    sold_like_filters = [
        "buyingOptions:{FIXED_PRICE},priceCurrency:USD,soldItemsOnly:true",
        "buyingOptions:{FIXED_PRICE},priceCurrency:USD,itemEndDate:[2025-01-01T00:00:00Z..]",
        "buyingOptions:{FIXED_PRICE},priceCurrency:USD",
    ]
    for filter_value in sold_like_filters:
        status, payload, raw = request_json(
            "GET",
            url,
            headers=headers,
            params={
                "q": SEARCH_QUERIES[0],
                "filter": filter_value,
                "limit": "50",
                "sort": "newlyListed",
            },
            retries=1,
        )
        if status == 200:
            total = payload.get("total") if isinstance(payload, dict) else "?"
            log.info("Browse sold 필터 조합 응답 성공: filter=%r total=%s", filter_value, total)
            items = extract_browse_items(payload, usd_to_krw, "browse_sold_filter_test")
            log.info(
                "Browse sold 필터 조합 매칭 item=%s. Browse search 응답은 active listing일 수 있어 체결가로 저장하지 않음",
                len(items),
            )
        else:
            log.warning(
                "Browse sold 필터 조합 실패: HTTP %s filter=%r | %s",
                status,
                filter_value,
                summarize_error(payload, raw),
            )


def fetch_finding_completed(usd_to_krw: float) -> list[dict[str, Any]]:
    url = "https://svcs.ebay.com/services/search/FindingService/v1"
    out: list[dict[str, Any]] = []
    seen: set[str] = set()

    for query in SEARCH_QUERIES:
        params = {
            "OPERATION-NAME": "findCompletedItems",
            "SERVICE-VERSION": "1.13.0",
            "SECURITY-APPNAME": EBAY_APP_ID,
            "RESPONSE-DATA-FORMAT": "JSON",
            "REST-PAYLOAD": "true",
            "keywords": query,
            "paginationInput.entriesPerPage": "50",
            "sortOrder": "EndTimeSoonest",
            "itemFilter(0).name": "SoldItemsOnly",
            "itemFilter(0).value": "true",
            "itemFilter(1).name": "Currency",
            "itemFilter(1).value": "USD",
        }
        status, payload, raw = request_json("GET", url, params=params, retries=5)
        if status != 200:
            log.warning(
                "Finding findCompletedItems 실패: HTTP %s q=%r | %s",
                status,
                query,
                summarize_error(payload, raw),
            )
            continue

        response = {}
        if isinstance(payload, dict):
            response = (payload.get("findCompletedItemsResponse") or [{}])[0]
        ack = (response.get("ack") or [""])[0]
        if ack not in ("Success", "Warning"):
            log.warning("Finding 응답 실패: q=%r ack=%s | %s", query, ack, summarize_error(payload, raw))
            continue

        items = (
            response.get("searchResult", [{}])[0].get("item", [])
            if isinstance(response.get("searchResult"), list)
            else []
        )
        log.info("Finding findCompletedItems 성공: q=%r item=%s", query, len(items))

        for item in items:
            title = (item.get("title") or [""])[0]
            if not title_matches(title):
                continue
            selling = (item.get("sellingStatus") or [{}])[0]
            price_obj = (selling.get("currentPrice") or [{}])[0]
            if price_obj.get("@currencyId") != "USD":
                continue
            usd = parse_amount(price_obj.get("__value__"))
            if usd is None or usd < 5 or usd > 5000:
                continue
            url_value = (item.get("viewItemURL") or [""])[0]
            key = url_value or f"{title}:{usd}"
            if key in seen:
                continue
            seen.add(key)
            end_time_raw = (((item.get("listingInfo") or [{}])[0]).get("endTime") or [""])[0]
            traded_at = datetime.now(timezone.utc)
            if end_time_raw:
                try:
                    traded_at = datetime.fromisoformat(end_time_raw.replace("Z", "+00:00"))
                except ValueError:
                    pass
            out.append(
                usd_to_price_item(
                    usd,
                    usd_to_krw,
                    title=title,
                    source_detail="finding_completed_sold",
                    traded_at=traded_at,
                    url=url_value,
                )
            )
    return out


def fetch_marketplace_insights(token: str, usd_to_krw: float) -> list[dict[str, Any]]:
    url = "https://api.ebay.com/buy/marketplace_insights/v1_beta/item_sales/search"
    headers = {
        "Authorization": f"Bearer {token}",
        "X-EBAY-C-MARKETPLACE-ID": MARKETPLACE_ID,
    }
    out: list[dict[str, Any]] = []

    for query in SEARCH_QUERIES:
        status, payload, raw = request_json(
            "GET",
            url,
            headers=headers,
            params={"q": query, "limit": "50", "filter": "priceCurrency:USD"},
            retries=2,
        )
        if status != 200:
            log.warning(
                "Marketplace Insights 실패: HTTP %s q=%r | %s",
                status,
                query,
                summarize_error(payload, raw),
            )
            continue

        total = payload.get("total") if isinstance(payload, dict) else "?"
        log.info("Marketplace Insights 성공: q=%r total=%s", query, total)
        if not isinstance(payload, dict):
            continue
        for item in payload.get("itemSales", []) or []:
            title = str(item.get("title") or "")
            if not title_matches(title):
                continue
            price_obj = item.get("price") or {}
            if price_obj.get("currency") != "USD":
                continue
            usd = parse_amount(price_obj.get("value"))
            if usd is None or usd < 5 or usd > 5000:
                continue
            sold_date = item.get("lastSoldDate") or item.get("itemSoldDate")
            traded_at = datetime.now(timezone.utc)
            if sold_date:
                try:
                    traded_at = datetime.fromisoformat(str(sold_date).replace("Z", "+00:00"))
                except ValueError:
                    pass
            out.append(
                usd_to_price_item(
                    usd,
                    usd_to_krw,
                    title=title,
                    source_detail="marketplace_insights",
                    traded_at=traded_at,
                    url=str(item.get("itemWebUrl") or ""),
                )
            )
    return out


def choose_active_median(active_items: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not active_items:
        return []
    prices = sorted(item["price"] for item in active_items)
    median_price = int(round(statistics.median(prices)))
    closest = min(active_items, key=lambda item: abs(item["price"] - median_price))
    fallback = dict(closest)
    fallback["price"] = median_price
    fallback["source_detail"] = "browse_active_median_fallback"
    fallback["traded_at"] = datetime.now(timezone.utc)
    log.warning(
        "체결가 수집 실패 -> active listing 중앙값 fallback 사용: %s원 (%s개 active)",
        f"{median_price:,}",
        len(active_items),
    )
    return [fallback]


def already_collected_recently(conn) -> bool:
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT COUNT(*) FROM price_snapshots
            WHERE card_id = %s AND source = 'EBAY'
              AND collected_at > NOW() - INTERVAL '6 hours'
            """,
            (CARD_ID,),
        )
        return cur.fetchone()[0] > 0


def save_prices(conn, items: list[dict[str, Any]]) -> int:
    saved = 0
    with conn.cursor() as cur:
        for item in items:
            snap_id = "SNAP_" + uuid.uuid4().hex[:20].upper()
            cur.execute(
                """
                INSERT INTO price_snapshots
                  (price_snapshot_id, card_id, source, price,
                   card_status, grading_company, grade_value, title,
                   traded_at, collected_at)
                VALUES (%s, %s, 'EBAY', %s, %s, %s, %s, %s, %s, NOW())
                """,
                (
                    snap_id,
                    CARD_ID,
                    item["price"],
                    item.get("card_status", "RAW"),
                    item.get("grading_company"),
                    item.get("grade_value"),
                    item.get("title", "")[:500],
                    item["traded_at"],
                ),
            )
            saved += 1
            log.info(
                "저장: %s원 | $%.2f | %s/%s | %s | %s",
                f"{item['price']:,}",
                item.get("usd", 0.0),
                item.get("grading_company") or "RAW",
                item.get("grade_value") or "-",
                item.get("source_detail", ""),
                item.get("title", "")[:60],
            )
    conn.commit()
    log.info("EBAY %s건 저장 완료", saved)
    return saved


def main() -> None:
    log.info("=== %s 가격 수집 시작 ===", CARD_NAME)

    usd_to_krw = get_usd_to_krw()

    base_token = get_oauth_token(["https://api.ebay.com/oauth/api_scope"])
    feed_scope_token = get_oauth_token(
        [
            "https://api.ebay.com/oauth/api_scope",
            "https://api.ebay.com/oauth/api_scope/buy.item.feed",
        ]
    )

    active_items: list[dict[str, Any]] = []
    sold_items: list[dict[str, Any]] = []

    if base_token:
        active_items = fetch_browse_active(base_token, usd_to_krw)
        log.info("Browse active 매칭 결과: %s개", len(active_items))
        fetch_browse_sold_filter_tests(base_token, usd_to_krw)

    finding_items = fetch_finding_completed(usd_to_krw)
    if finding_items:
        log.info("Finding 체결가 매칭 결과: %s개", len(finding_items))
        sold_items.extend(finding_items)

    if feed_scope_token:
        insights_items = fetch_marketplace_insights(feed_scope_token, usd_to_krw)
        if insights_items:
            log.info("Marketplace Insights 체결가 매칭 결과: %s개", len(insights_items))
            sold_items.extend(insights_items)

    items_to_save = sold_items if sold_items else choose_active_median(active_items)
    if not items_to_save:
        log.error("저장할 가격 데이터 없음: 체결가와 active listing 모두 수집 실패")
        return

    prices = sorted(item["price"] for item in items_to_save)
    log.info(
        "저장 가격 범위: %s원 ~ %s원 | 중앙값: %s원 | 건수: %s",
        f"{min(prices):,}",
        f"{max(prices):,}",
        f"{int(round(statistics.median(prices))):,}",
        len(prices),
    )

    conn = psycopg2.connect(DB_DSN)
    try:
        if already_collected_recently(conn):
            log.info("최근 6시간 이내 EBAY 수집 데이터가 있어 저장 스킵")
            return
        save_prices(conn, items_to_save)
    finally:
        conn.close()

    log.info("완료")


if __name__ == "__main__":
    main()
