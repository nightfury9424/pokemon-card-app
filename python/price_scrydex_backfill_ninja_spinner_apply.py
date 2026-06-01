#!/usr/bin/env python3
"""
price_scrydex_backfill_ninja_spinner_apply.py
==============================================
닌자스피너 27장 한정 Scrydex historical backfill — 정식 INSERT.

[전제]
2026-05-30 dry-run (price_scrydex_backfill_ninja_spinner_dryrun.py) 통과 확인.
- 27/27 fetch + parse 성공
- 시계열 2026-05-16 ~ 2026-05-29 (14일)
- SCRYDEX_JP 신규 378건, 중복 0
- 산식 검증 99% 정확 (sim_KO_KRW vs 우리 시뮬레이션 일치)

[흐름]
1. fetch_html + parse_history (dry-run 과 동일)
2. save_history() 호출 — 실제 INSERT (insert_snapshot 내부에서 ON CONFLICT 방어)
3. requests.post KO_ESTIMATE_REFRESH_URL — 27 카드 KO_ESTIMATED 자동 계산
4. INSERT 후 통계 출력

[정책]
- 닌자스피너 27장 한정 — 다른 카드 SCRYDEX_JP 건드리지 않음
- KO refresh API 는 전체 KO 재계산이지만 산식 freeze → 다른 카드 결과 변화 0
- card_id + source + DATE(traded_at) idempotent (insert_snapshot 내부 처리)

[사용]
  docker exec pokefolio-back python3 /tmp/price_scrydex_backfill_ninja_spinner_apply.py
"""
from __future__ import annotations
import os
import sys
import time
import requests

sys.path.insert(0, "/app/python")
from price_scrydex import (
    get_conn, fetch_exchange_rates, fetch_html, parse_history, save_history,
    safe_print, SLEEP, KO_ESTIMATE_REFRESH_URL,
)

TARGET_PRODUCT_ID = "PRD_156BB71C4F5A41C39521"
TARGET_JP_REFS = [
    # SAR 6
    "m4_ja-114", "m4_ja-115", "m4_ja-116", "m4_ja-117", "m4_ja-118", "m4_ja-119",
    # AR 11 (095 보류)
    "m4_ja-84",  "m4_ja-85",  "m4_ja-86",  "m4_ja-87",  "m4_ja-88",  "m4_ja-89",
    "m4_ja-90",  "m4_ja-91",  "m4_ja-92",  "m4_ja-93",  "m4_ja-94",
    # SR 10 (104-107 ITEM/TOOL, 109/111 보류, 112-113 STADIUM 제외)
    "m4_ja-96",  "m4_ja-97",  "m4_ja-98",  "m4_ja-99",  "m4_ja-100",
    "m4_ja-101", "m4_ja-102", "m4_ja-103", "m4_ja-108", "m4_ja-110",
]


def fetch_target_cards(conn):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT card_id, collection_number, rarity_code, name, jp_scrydex_ref
            FROM cards
            WHERE product_id = %s
              AND language = 'KO'
              AND is_visible = TRUE
              AND jp_scrydex_ref = ANY(%s)
            ORDER BY CAST(regexp_replace(collection_number, '/.*', '') AS int)
        """, (TARGET_PRODUCT_ID, TARGET_JP_REFS))
        return cur.fetchall()


def main():
    print("=" * 80)
    print("닌자스피너 Scrydex backfill — APPLY (실제 INSERT)")
    print("=" * 80)

    usd_krw, jpy_krw = fetch_exchange_rates()
    print(f"환율 : USD/KRW={usd_krw:.0f}, JPY/KRW={jpy_krw:.2f}")
    print()

    conn = get_conn()
    cards = fetch_target_cards(conn)
    print(f"DB 매칭: {len(cards)}장 (기대 27)")
    if len(cards) != 27:
        print(f"⚠️ WARNING: 27장 기대 vs {len(cards)}장 — 중단")
        conn.close()
        return 1
    print()

    total_saved = 0
    failures = []

    for i, (card_id, col, rarity, name, jp_ref) in enumerate(cards, 1):
        col_int = col.split("/")[0]
        short_name = name[:18]

        html = fetch_html(jp_ref)
        if not html:
            print(f"[{i:>2}/{len(cards)}] {col_int} {rarity:>3} {short_name:<20} {jp_ref:<12} FETCH_FAIL")
            failures.append((card_id, jp_ref, "fetch_html None"))
            continue

        try:
            raw_nm, psa10, psa9, raw_is_krw, raw_is_jpy = parse_history(html, is_jp=True, jpy_krw=jpy_krw)
        except Exception as e:
            print(f"[{i:>2}/{len(cards)}] {col_int} {rarity:>3} {short_name:<20} {jp_ref:<12} PARSE_FAIL: {e}")
            failures.append((card_id, jp_ref, f"parse: {e}"))
            continue

        if not raw_nm:
            print(f"[{i:>2}/{len(cards)}] {col_int} {rarity:>3} {short_name:<20} {jp_ref:<12} NO_RAW")
            failures.append((card_id, jp_ref, "raw_nm empty"))
            continue

        # process_card 와 동일 패턴 (KO 카드 = is_jp 항상 True)
        raw_rate = jpy_krw if raw_is_jpy else usd_krw
        try:
            saved = save_history(
                conn, card_id, "SCRYDEX_JP", raw_nm, psa10, psa9,
                rarity or "",
                since_date=None, usd_krw=usd_krw, raw_is_krw=raw_is_krw,
                skip_sanitize=True,  # JP 카드 skip_sanitize 패턴
                raw_rate=raw_rate, raw_is_jpy=raw_is_jpy,
            )
            total_saved += saved
            print(f"[{i:>2}/{len(cards)}] {col_int} {rarity:>3} {short_name:<20} {jp_ref:<12} RAW={len(raw_nm)} saved={saved}")
        except Exception as e:
            print(f"[{i:>2}/{len(cards)}] {col_int} {rarity:>3} {short_name:<20} {jp_ref:<12} SAVE_FAIL: {e}")
            failures.append((card_id, jp_ref, f"save: {e}"))

        time.sleep(SLEEP)

    conn.close()

    print()
    print("=" * 80)
    print(f"SCRYDEX_JP INSERT 완료: 총 {total_saved}건  (실패 {len(failures)})")
    if failures:
        print("FAILURES:")
        for cid, ref, err in failures:
            print(f"  {cid[:24]} ({ref}): {err}")

    # KO_ESTIMATE_REFRESH 호출
    print()
    print("=" * 80)
    print(f"KO_ESTIMATE_REFRESH POST → {KO_ESTIMATE_REFRESH_URL}")
    try:
        resp = requests.post(KO_ESTIMATE_REFRESH_URL, timeout=120)
        print(f"  status={resp.status_code}  body[:200]={resp.text[:200]}")
    except Exception as e:
        print(f"  REFRESH FAIL: {e}")
        print(f"  (수동으로 백엔드 admin 호출 또는 cron 자연 대기)")

    print()
    print("=" * 80)
    print("DONE")


if __name__ == "__main__":
    sys.exit(main() or 0)
