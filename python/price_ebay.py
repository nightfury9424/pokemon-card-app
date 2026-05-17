"""
eBay Finding API 교차검증 모듈.
scrydex 가격이 이상하게 보일 때만 호출 — 평상시엔 건드리지 않음.

Usage (standalone):
    python price_ebay.py --col "207/XY-P" --grade 10
"""

import argparse
import statistics
from typing import Optional

import requests

try:
    from config import EBAY_APP_ID
except ImportError:
    EBAY_APP_ID = None

FINDING_API = "https://svcs.ebay.com/services/search/FindingService/v1"
POKEMON_CATEGORY = "2536"   # Collectible Card Games > Pokemon


# ─────────────────────────────────────────────────────────────
# 1) eBay completed sales 검색
# ─────────────────────────────────────────────────────────────

def search_sold_psa(collection_number: str, grade: str = "10", limit: int = 20) -> list:
    """
    eBay 낙찰가 조회.
    collection_number: "207/XY-P" 형태 — 슬래시 포함 그대로 전달
    반환: USD 가격 리스트 (최근 낙찰가)
    """
    if not EBAY_APP_ID:
        return []

    query = f'pokemon japanese "{collection_number}" PSA {grade}'

    params = {
        "OPERATION-NAME":           "findCompletedItems",
        "SERVICE-VERSION":          "1.13.0",
        "SECURITY-APPNAME":         EBAY_APP_ID,
        "RESPONSE-DATA-FORMAT":     "JSON",
        "keywords":                 query,
        "categoryId":               POKEMON_CATEGORY,
        "itemFilter(0).name":       "SoldItemsOnly",
        "itemFilter(0).value":      "true",
        "sortOrder":                "EndTimeSoonest",
        "paginationInput.entriesPerPage": str(limit),
    }

    try:
        resp = requests.get(FINDING_API, params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()

        result = data.get("findCompletedItemsResponse", [{}])[0]
        ack = result.get("ack", ["Failure"])[0]
        if ack != "Success":
            errors = result.get("errorMessage", [{}])[0].get("error", [{}])[0]
            print(f"  [EBAY] API 오류: {errors.get('message', ['?'])[0]}")
            return []

        items = result.get("searchResult", [{}])[0].get("item", [])
        prices = []
        for item in items:
            try:
                price_str = item["sellingStatus"][0]["convertedCurrentPrice"][0]["__value__"]
                prices.append(float(price_str))
            except (KeyError, IndexError, ValueError):
                continue
        return prices

    except Exception as e:
        print(f"  [EBAY] 검색 실패 ({collection_number} PSA{grade}): {e}")
        return []


# ─────────────────────────────────────────────────────────────
# 1-b) RAW NM sold listings (REFACTOR_2026-05-12.md 2-③)
# ─────────────────────────────────────────────────────────────

def search_sold_raw(
    collection_number: str,
    name: Optional[str] = None,
    limit: int = 20,
) -> list:
    """
    eBay RAW NM 낙찰가 조회. PSA/BGS/BRG/CGC/ACE 등 grading 키워드 제외.
    collection_number: "207/XY-P" 형태 (슬래시 포함)
    name: 영문 카드명 (있으면 정확도 ↑)
    반환: USD sold price 리스트
    """
    if not EBAY_APP_ID:
        return []

    parts = ['pokemon', f'"{collection_number}"', 'near mint',
            '-PSA', '-BGS', '-BRG', '-CGC', '-ACE', '-graded', '-slab']
    if name:
        parts.insert(2, f'"{name}"')
    query = ' '.join(parts)

    params = {
        "OPERATION-NAME":           "findCompletedItems",
        "SERVICE-VERSION":          "1.13.0",
        "SECURITY-APPNAME":         EBAY_APP_ID,
        "RESPONSE-DATA-FORMAT":     "JSON",
        "keywords":                 query,
        "categoryId":               POKEMON_CATEGORY,
        "itemFilter(0).name":       "SoldItemsOnly",
        "itemFilter(0).value":      "true",
        "sortOrder":                "EndTimeSoonest",
        "paginationInput.entriesPerPage": str(limit),
    }

    try:
        resp = requests.get(FINDING_API, params=params, timeout=15)
        resp.raise_for_status()
        data = resp.json()

        result = data.get("findCompletedItemsResponse", [{}])[0]
        ack = result.get("ack", ["Failure"])[0]
        if ack != "Success":
            return []

        items = result.get("searchResult", [{}])[0].get("item", [])
        prices = []
        for item in items:
            try:
                price_str = item["sellingStatus"][0]["convertedCurrentPrice"][0]["__value__"]
                prices.append(float(price_str))
            except (KeyError, IndexError, ValueError):
                continue
        return prices
    except Exception as e:
        print(f"  [EBAY] RAW NM 검색 실패 ({collection_number}): {e}")
        return []


def raw_sales_summary(
    collection_number: str,
    name: Optional[str] = None,
) -> dict:
    """RAW NM eBay sold 요약 — UI 신뢰도 라벨용.
    반환: {'count': int, 'median': float | None, 'low': float | None, 'high': float | None}
    count=0이면 '추정가 — 실거래 없음' 라벨 트리거.
    """
    prices = search_sold_raw(collection_number, name)
    if not prices:
        return {'count': 0, 'median': None, 'low': None, 'high': None}
    return {
        'count': len(prices),
        'median': statistics.median(prices),
        'low': min(prices),
        'high': max(prices),
    }


# ─────────────────────────────────────────────────────────────
# 2) 교차검증 — True=정상수용 / False=오염기각
# ─────────────────────────────────────────────────────────────

CONTAMINATION_RATIO = 0.25   # scrydex 가격이 eBay 중앙값의 25% 미만이면 오염


def validate_price(
    collection_number: str,
    grade: str,
    suspect_usd: float,
    hist_median_usd: Optional[float] = None,
) -> bool:
    """
    suspect_usd (USD)가 정상 가격인지 eBay 낙찰가로 검증.

    True  → 저장 OK  (정상이거나 판단 불가)
    False → 저장 SKIP (eBay 기준 오염 확인)
    """
    ebay_prices = search_sold_psa(collection_number, grade)

    if not ebay_prices:
        # eBay 결과 없으면 판단 불가 → 보수적으로 수용
        print(f"  [EBAY] {collection_number} PSA{grade}: 결과 없음 → 수용")
        return True

    ebay_median = statistics.median(ebay_prices)
    ratio = suspect_usd / ebay_median if ebay_median > 0 else 0

    print(
        f"  [EBAY] {collection_number} PSA{grade}: "
        f"scrydex=${suspect_usd:,.0f}  eBay중앙값=${ebay_median:,.0f}  "
        f"비율={ratio:.1%}  샘플={len(ebay_prices)}건"
    )

    if ratio < CONTAMINATION_RATIO:
        print(f"  [EBAY] → 오염 확인. scrydex 데이터 기각.")
        return False

    return True


# ─────────────────────────────────────────────────────────────
# CLI (단독 실행 테스트)
# ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="eBay 가격 교차검증 테스트")
    parser.add_argument("--col",   required=True, help='수록번호 예) "207/XY-P"')
    parser.add_argument("--grade", default="10",  help="PSA 등급 (기본: 10)")
    args = parser.parse_args()

    prices = search_sold_psa(args.col, args.grade)
    if prices:
        print(f"\neBay 낙찰가 ({len(prices)}건): {prices}")
        print(f"중앙값: ${statistics.median(prices):,.0f}")
        print(f"평균:   ${sum(prices)/len(prices):,.0f}")
    else:
        print("결과 없음")
