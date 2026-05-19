#!/usr/bin/env python3
"""
mirror_card_images_to_s3.py

Pokemon card master images → S3 cards/v1/ mirror.

[전략]
- jp_scrydex_ref 정상 카드 → S3 cards/v1/jp/{cardId}.png   (from scrydex CDN)
- en_scrydex_ref 정상 카드 → S3 cards/v1/en/{cardId}.png   (from scrydex CDN)
- jp/en 둘 다 NO_/null 카드 → S3 cards/v1/special/{cardId}.png
    (from local scanner/data/cards/{cardId}_jp.png — _jp 없으면 _en, 없으면 fail)
- KO 이미지는 이번 단계에서 제외.

[안전장치]
- Resumable: S3 HEAD으로 이미 있으면 skip
- Rate limit: --rate (default 8 req/s) for scrydex CDN
- Retry: backoff 0.5/1/2 sec, 최대 3회
- Dry-run: --dry-run 플래그 (DB만 읽고 plan/카운트/sample/reachability test)
- Failure log: mirror_failures_YYYYMMDD_HHMM.csv

[환경변수]
DB_HOST(localhost) / DB_PORT(5432) / DB_USER(nightfury) / DB_PASSWORD / DB_NAME(pokemon_card_db)
AWS_REGION(ap-northeast-2) / AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
S3_BUCKET / S3_CARDS_PREFIX(cards/v1)
LOCAL_CARDS_DIR (default: <repo>/scanner/data/cards)

[사용]
    python python/mirror_card_images_to_s3.py --dry-run
    python python/mirror_card_images_to_s3.py --only special
    python python/mirror_card_images_to_s3.py
"""

import argparse
import csv
import os
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Tuple

import psycopg2
from psycopg2.extras import RealDictCursor
import requests

# boto3 is optional for dry-run
try:
    import boto3
    from botocore.exceptions import ClientError
    BOTO3_OK = True
except ImportError:
    BOTO3_OK = False
    ClientError = Exception  # type: ignore


SCRYDEX_CDN_FMT = "https://images.scrydex.com/pokemon/{ref}/medium"
USER_AGENT = "PokefolioBatchMirror/1.0"

DEFAULT_BUCKET = "pokefolio-beta-assets-759135635310-ap-northeast-2-an"
DEFAULT_PREFIX = "cards/v1"
DEFAULT_LOCAL_DIR = str(Path(__file__).resolve().parent.parent / "scanner/data/cards")
DEFAULT_REGION = "ap-northeast-2"


def get_db():
    return psycopg2.connect(
        host=os.environ.get("DB_HOST", "localhost"),
        port=int(os.environ.get("DB_PORT", "5432")),
        user=os.environ.get("DB_USER", "nightfury"),
        password=os.environ.get("DB_PASSWORD", ""),
        dbname=os.environ.get("DB_NAME", "pokemon_card_db"),
    )


def _is_valid_ref(ref: Optional[str]) -> bool:
    return bool(ref) and not ref.startswith("NO_") and ref.strip() != ""


def fetch_cards() -> Tuple[List[Tuple[str, str, str]], List[Tuple[str, str, str]], List[Tuple[str, str]]]:
    """cards 테이블 → (jp_list, en_list, special_list).

    jp_list: [(card_id, jp_ref, name), ...]   jp ref 정상 카드
    en_list: [(card_id, en_ref, name), ...]   en ref 정상 카드
    special_list: [(card_id, name), ...]      둘 다 없는 카드
    """
    sql = """
        SELECT card_id, name, jp_scrydex_ref, en_scrydex_ref
        FROM cards
        ORDER BY card_id
    """
    jp_list, en_list, special_list = [], [], []
    with get_db() as conn, conn.cursor(cursor_factory=RealDictCursor) as cur:
        cur.execute(sql)
        for r in cur.fetchall():
            cid = r["card_id"]
            name = r["name"]
            jp_ref = r["jp_scrydex_ref"]
            en_ref = r["en_scrydex_ref"]
            jp_ok = _is_valid_ref(jp_ref)
            en_ok = _is_valid_ref(en_ref)
            if jp_ok:
                jp_list.append((cid, jp_ref, name))
            if en_ok:
                en_list.append((cid, en_ref, name))
            if not jp_ok and not en_ok:
                special_list.append((cid, name))
    return jp_list, en_list, special_list


def s3_head_exists(s3, bucket: str, key: str) -> bool:
    try:
        s3.head_object(Bucket=bucket, Key=key)
        return True
    except ClientError as e:
        code = e.response.get("Error", {}).get("Code", "")
        if code in ("404", "NoSuchKey", "NotFound"):
            return False
        raise


def download_scrydex(ref: str, retries: int = 3) -> Optional[bytes]:
    url = SCRYDEX_CDN_FMT.format(ref=ref)
    for attempt in range(retries):
        try:
            r = requests.get(url, headers={"User-Agent": USER_AGENT}, timeout=15)
            if r.status_code == 200:
                return r.content
            if r.status_code in (404, 403):
                # retry 의미 없음
                return None
        except requests.RequestException:
            pass
        time.sleep(0.5 * (2 ** attempt))
    return None


def upload(s3, bucket: str, key: str, body: bytes) -> None:
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=body,
        ContentType="image/png",
        # cards/v1/{id}.png는 사실상 immutable — 카드 이미지 갱신 시 cards/v2로 prefix 올림.
        # immutable 헤더로 브라우저/OS 캐시가 reload에도 재요청 없이 사용 → S3 egress 절약.
        CacheControl="public, max-age=31536000, immutable",
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="계획만 출력, 업로드 X")
    parser.add_argument("--only", choices=["jp", "en", "special"], default=None,
                        help="특정 카테고리만 처리")
    parser.add_argument("--rate", type=float, default=8.0,
                        help="scrydex CDN 요청 속도 (req/s). 기본 8.")
    parser.add_argument("--limit", type=int, default=None,
                        help="테스트용 처리 개수 제한 (uploaded + skipped 기준)")
    args = parser.parse_args()

    bucket = os.environ.get("S3_BUCKET", DEFAULT_BUCKET)
    prefix = os.environ.get("S3_CARDS_PREFIX", DEFAULT_PREFIX).rstrip("/")
    local_dir = Path(os.environ.get("LOCAL_CARDS_DIR", DEFAULT_LOCAL_DIR))
    region = os.environ.get("AWS_REGION", DEFAULT_REGION)

    print("=" * 60)
    print(f"[Bucket]   {bucket}")
    print(f"[Prefix]   {prefix}")
    print(f"[Region]   {region}")
    print(f"[Local]    {local_dir}")
    print(f"[Mode]     {'DRY-RUN' if args.dry_run else 'REAL UPLOAD'}")
    print(f"[Filter]   {args.only or 'all'}")
    print(f"[Rate]     {args.rate} req/s")
    if args.limit:
        print(f"[Limit]    {args.limit}")
    print("=" * 60)
    print()

    # 1. DB 조회
    print("=== DB 조회 ===")
    try:
        jp_list, en_list, special_list = fetch_cards()
    except Exception as e:
        print(f"  FAIL — DB connect/query 실패: {e}")
        sys.exit(2)
    total_upload_count = len(jp_list) + len(en_list) + len(special_list)
    print(f"  jp valid 카드:  {len(jp_list)}")
    print(f"  en valid 카드:  {len(en_list)}")
    print(f"  special 카드:   {len(special_list)}")
    print(f"  업로드 대상 키 수 (jp + en + special): {total_upload_count}")
    print()

    # 2. special source 검증
    print("=== special source 검증 (로컬 PNG 존재 여부) ===")
    special_sources = []
    for cid, name in special_list:
        jp_path = local_dir / f"{cid}_jp.png"
        en_path = local_dir / f"{cid}_en.png"
        if jp_path.exists():
            src = jp_path
            note = "_jp.png"
        elif en_path.exists():
            src = en_path
            note = "_en.png (jp 없음)"
        else:
            src = None
            note = "NOT FOUND"
        special_sources.append((cid, name, src))
        print(f"  {cid} ({name}) → {note}")
    print()

    # 3. dry-run 추가 검증
    if args.dry_run:
        # 3-1. sample 출력
        print("=== sample 키 미리보기 ===")
        for cid, ref, name in jp_list[:3]:
            print(f"  jp:  {ref:30s} → s3://{bucket}/{prefix}/jp/{cid}.png   ({name})")
        for cid, ref, name in en_list[:3]:
            print(f"  en:  {ref:30s} → s3://{bucket}/{prefix}/en/{cid}.png   ({name})")
        for cid, name, src in special_sources:
            src_str = src.name if src else "MISSING"
            print(f"  spc: {src_str:30s} → s3://{bucket}/{prefix}/special/{cid}.png   ({name})")
        print()

        # 3-2. scrydex reach test (jp 1장)
        if jp_list:
            ref = jp_list[0][1]
            print(f"=== scrydex CDN reachability test ({ref}) ===")
            t0 = time.time()
            data = download_scrydex(ref, retries=1)
            dt = (time.time() - t0) * 1000
            if data:
                print(f"  OK — {len(data):,} bytes, {dt:.0f}ms")
            else:
                print(f"  FAIL — scrydex CDN에서 받을 수 없음 (ref={ref})")
            print()

        # 3-3. S3 credential test (선택)
        print("=== S3 credential test ===")
        if not BOTO3_OK:
            print("  SKIP — boto3 not installed. 실제 업로드 전에 설치 필요:")
            print("           pip install boto3")
        else:
            try:
                s3 = boto3.client("s3", region_name=region)
                s3.head_bucket(Bucket=bucket)
                print(f"  OK — bucket head 성공 (region={region})")
            except ClientError as e:
                code = e.response.get("Error", {}).get("Code", "")
                msg = e.response.get("Error", {}).get("Message", "")
                print(f"  FAIL — {code}: {msg}")
            except Exception as e:
                print(f"  SKIP — credential 미설정 또는 기타: {e}")
        print()

        print("DRY-RUN 완료. 실제 업로드는 --dry-run 빼고 실행.")
        return

    # 4. 실제 업로드
    if not BOTO3_OK:
        print("ERROR: boto3 not installed. 실행:")
        print("  pip install boto3")
        sys.exit(1)

    s3 = boto3.client("s3", region_name=region)

    sleep_per = 1.0 / args.rate
    failures: List[Tuple[str, str, str, str]] = []
    skipped = 0
    uploaded = 0

    def process_lang(items: List[Tuple[str, str, str]], lang: str) -> None:
        nonlocal skipped, uploaded
        if args.only and args.only != lang:
            return
        for cid, ref, _name in items:
            if args.limit and (uploaded + skipped) >= args.limit:
                return
            key = f"{prefix}/{lang}/{cid}.png"
            try:
                if s3_head_exists(s3, bucket, key):
                    skipped += 1
                    continue
            except Exception as e:
                failures.append((cid, lang, ref, f"head_failed: {e}"))
                continue
            data = download_scrydex(ref)
            if not data:
                failures.append((cid, lang, ref, "download_failed"))
                continue
            try:
                upload(s3, bucket, key, data)
                uploaded += 1
            except Exception as e:
                failures.append((cid, lang, ref, f"upload_failed: {e}"))
            if uploaded > 0 and uploaded % 50 == 0:
                print(f"  [{lang}] uploaded={uploaded}, skipped={skipped}, failed={len(failures)}")
            time.sleep(sleep_per)

    def process_special() -> None:
        nonlocal skipped, uploaded
        if args.only and args.only != "special":
            return
        for cid, _name, src in special_sources:
            key = f"{prefix}/special/{cid}.png"
            try:
                if s3_head_exists(s3, bucket, key):
                    skipped += 1
                    continue
            except Exception as e:
                failures.append((cid, "special", "", f"head_failed: {e}"))
                continue
            if not src:
                failures.append((cid, "special", "", "local_source_missing"))
                continue
            try:
                upload(s3, bucket, key, src.read_bytes())
                uploaded += 1
                print(f"  [special] uploaded {cid} ← {src.name}")
            except Exception as e:
                failures.append((cid, "special", str(src), f"upload_failed: {e}"))

    print("=== upload 시작 ===")
    process_special()
    process_lang(jp_list, "jp")
    process_lang(en_list, "en")

    print()
    print(f"uploaded: {uploaded}")
    print(f"skipped:  {skipped}")
    print(f"failed:   {len(failures)}")

    if failures:
        ts = datetime.now().strftime("%Y%m%d_%H%M")
        log_path = Path(__file__).parent / f"mirror_failures_{ts}.csv"
        with open(log_path, "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["card_id", "lang", "ref", "error"])
            w.writerows(failures)
        print(f"failures log → {log_path}")


if __name__ == "__main__":
    main()
