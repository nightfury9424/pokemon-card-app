"""
Phase B.2 — boxes/ 의 WebP 들을 S3 boxes/v1/{product_id}.webp 로 업로드.

S3 정책 (cards/v1 패턴 동일 — project_image_system_s3):
  - bucket: pokefolio-beta-assets-...
  - key: boxes/v1/{product_id}.webp
  - Cache-Control: public, max-age=31536000, immutable
  - Content-Type: image/webp

자격은 환경변수 또는 .env.prod 로 받음.

실행:
  AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... AWS_S3_BUCKET=... \\
    /Users/fury/miniconda3/envs/scanner_v2/bin/python upload_s3.py
"""

from __future__ import annotations
import os
import sys
import time
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

HERE = Path(__file__).parent
BOXES = HERE / "boxes"

BUCKET = os.environ.get("AWS_S3_BUCKET")
REGION = os.environ.get("AWS_S3_REGION", "ap-northeast-2")
PREFIX = "boxes/v1"


def main() -> int:
    if not BUCKET:
        print("[err] AWS_S3_BUCKET 환경변수 필요", file=sys.stderr)
        return 1
    if not os.environ.get("AWS_ACCESS_KEY_ID") or not os.environ.get("AWS_SECRET_ACCESS_KEY"):
        print("[err] AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY 환경변수 필요", file=sys.stderr)
        return 1

    files = sorted(BOXES.glob("*.webp"))
    if not files:
        print(f"[err] {BOXES} 에 .webp 없음", file=sys.stderr)
        return 1

    s3 = boto3.client("s3", region_name=REGION)

    print(f"[upload] {len(files)} → s3://{BUCKET}/{PREFIX}/", file=sys.stderr)
    ok, fail, skip = 0, 0, 0
    t0 = time.time()

    for i, f in enumerate(files, 1):
        key = f"{PREFIX}/{f.name}"
        try:
            # 이미 있으면 skip — 같은 사이즈/etag 비교는 over-engineering.
            try:
                s3.head_object(Bucket=BUCKET, Key=key)
                print(f"  [{i:3}/{len(files)}] skip (이미 있음) {f.name}", file=sys.stderr)
                skip += 1
                continue
            except ClientError as e:
                if e.response["Error"]["Code"] not in ("404", "NoSuchKey"):
                    raise

            s3.upload_file(
                str(f), BUCKET, key,
                ExtraArgs={
                    "ContentType": "image/webp",
                    "CacheControl": "public, max-age=31536000, immutable",
                    # ACL 제거 — 이 버킷은 ACL 비활성 (BucketOwnerEnforced).
                    # public read 는 별도 bucket policy 로 cards/v1 prefix 처리됨.
                    # boxes/v1 도 동일 정책 필요 시 별도 적용 (cards/v1 보면 됨).
                },
            )
            ok += 1
            if i % 10 == 0 or i == len(files):
                print(f"  [{i:3}/{len(files)}] ok ({ok} uploaded, {skip} skipped)", file=sys.stderr)
        except Exception as e:
            print(f"  [{i:3}/{len(files)}] FAIL {f.name}  {e}", file=sys.stderr)
            fail += 1

    elapsed = time.time() - t0
    print(f"\n[done] ok {ok} / skip {skip} / fail {fail} / {elapsed:.1f}s", file=sys.stderr)
    base_url = f"https://{BUCKET}.s3.{REGION}.amazonaws.com/{PREFIX}/"
    print(f"       base URL: {base_url}", file=sys.stderr)
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
