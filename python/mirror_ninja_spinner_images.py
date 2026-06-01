#!/usr/bin/env python3
"""
mirror_ninja_spinner_images.py — 닌자스피너 신규 27장 카드 이미지 S3 보강 (타겟 한정).

[배경]
2026-05-30 닌자스피너 KO master 27장 INSERT 완료 (SAR 6 + AR 11 + SR 10) 후,
image_url / local_image_path 모두 NULL → 도감에서 카드 뒷면으로 표시.
mirror_card_images_to_s3.py 는 전체 누락 카드 대상 — 본 cycle 영향 범위 한정 위해
27장만 타겟하는 wrapper.

[정책]
- product_id = PRD_156BB71C4F5A41C39521 (닌자스피너) 한정
- jp_scrydex_ref 명시 27개 (095/109/111 보류 + 도구 6장 제외 후)
- boxes 아니라 cards/v1/jp/{cardId}.png
- --dry-run 기본 (사용자 GO 후 --apply 로 실행)

[사용]
  docker exec pokefolio-back python3 /tmp/mirror_ninja_spinner_images.py --dry-run
  docker exec pokefolio-back python3 /tmp/mirror_ninja_spinner_images.py --apply
"""
from __future__ import annotations
import argparse
import os
import sys

sys.path.insert(0, "/app/python")
from mirror_card_images_to_s3 import (
    get_db, s3_head_exists, download_scrydex, upload,
    SCRYDEX_CDN_FMT, DEFAULT_BUCKET, DEFAULT_PREFIX, DEFAULT_REGION,
)

import boto3
import requests

TARGET_PRODUCT_ID = "PRD_156BB71C4F5A41C39521"
TARGET_JP_REFS = [
    # SAR 6장 (col 114-119)
    "m4_ja-114", "m4_ja-115", "m4_ja-116", "m4_ja-117", "m4_ja-118", "m4_ja-119",
    # AR 11장 (col 084-094, 095 Watchog 보류)
    "m4_ja-84",  "m4_ja-85",  "m4_ja-86",  "m4_ja-87",  "m4_ja-88",  "m4_ja-89",
    "m4_ja-90",  "m4_ja-91",  "m4_ja-92",  "m4_ja-93",  "m4_ja-94",
    # SR 10장 (col 096-103, 108, 110)
    # 제외: 104-107 ITEM/TOOL, 109 Philippe 보류, 111 Emma 보류, 112-113 STADIUM (프리즘타워 포함)
    "m4_ja-96",  "m4_ja-97",  "m4_ja-98",  "m4_ja-99",  "m4_ja-100",
    "m4_ja-101", "m4_ja-102", "m4_ja-103", "m4_ja-108", "m4_ja-110",
]

USER_AGENT = "PokefolioNinjaImage/1.0"


def fetch_target_cards(conn):
    with conn.cursor() as cur:
        cur.execute("""
            SELECT card_id, name, rarity_code, collection_number, jp_scrydex_ref
            FROM cards
            WHERE product_id = %s
              AND language = 'KO'
              AND is_visible = TRUE
              AND jp_scrydex_ref = ANY(%s)
            ORDER BY CAST(regexp_replace(collection_number, '/.*', '') AS int)
        """, (TARGET_PRODUCT_ID, TARGET_JP_REFS))
        return cur.fetchall()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true",
                        help="실제 S3 업로드. 기본은 dry-run.")
    args = parser.parse_args()
    dry_run = not args.apply

    bucket = os.environ.get("S3_BUCKET", os.environ.get("AWS_S3_BUCKET", DEFAULT_BUCKET))
    prefix = os.environ.get("S3_CARDS_PREFIX", DEFAULT_PREFIX)
    region = os.environ.get("AWS_REGION", DEFAULT_REGION)

    print(f"[Mode]     {'DRY-RUN' if dry_run else 'REAL UPLOAD'}")
    print(f"[Bucket]   {bucket}")
    print(f"[Prefix]   {prefix}")
    print(f"[Region]   {region}")
    print(f"[Target]   닌자스피너 27장 (PRD_156BB71C4F5A41C39521)")
    print(f"[Refs]     SAR 6 + AR 11 + SR 10")
    print()

    conn = get_db()
    cards = fetch_target_cards(conn)
    conn.close()

    print(f"DB query 결과: {len(cards)}장 매칭 (기대값 27)")
    if len(cards) != 27:
        print(f"⚠️  WARNING: 27장 기대했는데 {len(cards)}장 — 검토 필요")

    s3 = boto3.client("s3", region_name=region)

    print()
    print(f"{'#':>2} {'col':>3} {'rar':>3}  {'card_id (앞24)':<28} {'name':<20} {'jp_ref':<14} {'S3':<6} {'scrydex':<8} {'action':<14}")
    print("-" * 130)

    s3_exists_count = 0
    upload_planned = 0
    upload_success = 0
    upload_failure = 0
    scrydex_404 = 0
    failures = []

    for i, (card_id, name, rarity, col, jp_ref) in enumerate(cards, 1):
        key = f"{prefix}/jp/{card_id}.png"
        scrydex_url = SCRYDEX_CDN_FMT.format(ref=jp_ref)

        # S3 HEAD
        try:
            exists = s3_head_exists(s3, bucket, key)
        except Exception as e:
            exists = False
            failures.append((card_id, jp_ref, f"S3 HEAD error: {e}"))

        # scrydex reachability (dry-run + 없는 카드만)
        reach = "skip"
        if not exists:
            try:
                r = requests.head(scrydex_url, headers={"User-Agent": USER_AGENT}, timeout=8)
                reach = str(r.status_code)
                if r.status_code == 404:
                    scrydex_404 += 1
            except Exception as e:
                reach = "ERR"

        action = "SKIP(exists)" if exists else ("UPLOAD" if reach == "200" else "FAIL(reach)")
        if exists:
            s3_exists_count += 1
        elif reach == "200":
            upload_planned += 1

        col_int = col.split("/")[0]
        short_id = card_id[:24]
        short_name = (name[:18] + "..") if len(name) > 20 else name
        print(f"{i:>2} {col_int:>3} {rarity:>3}  {short_id:<28} {short_name:<20} {jp_ref:<14} {'✅' if exists else '❌':<6} {reach:<8} {action:<14}")

        # 정식 실행 모드
        if not dry_run and not exists and reach == "200":
            try:
                body = download_scrydex(jp_ref)
                if body is None:
                    upload_failure += 1
                    failures.append((card_id, jp_ref, "scrydex download None"))
                    continue
                upload(s3, bucket, key, body)
                upload_success += 1
            except Exception as e:
                upload_failure += 1
                failures.append((card_id, jp_ref, str(e)))

    print()
    print("=" * 60)
    print(f"S3 이미 존재    : {s3_exists_count}")
    print(f"업로드 가능     : {upload_planned}")
    print(f"scrydex 404     : {scrydex_404}")
    if not dry_run:
        print(f"업로드 성공     : {upload_success}")
        print(f"업로드 실패     : {upload_failure}")
    if failures:
        print()
        print("FAILURES:")
        for cid, ref, err in failures[:10]:
            print(f"  {cid} ({ref}): {err}")
        if len(failures) > 10:
            print(f"  ... and {len(failures)-10} more")

    if dry_run:
        print()
        print("→ 결과 OK 시 `--apply` 로 정식 실행")


if __name__ == "__main__":
    main()
