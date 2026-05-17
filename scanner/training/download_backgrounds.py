"""COCO 2017 val 데이터셋 다운로드 → 합성 학습용 배경.

5,000장 다양한 실내/실외 풍경. 카드 환경(책상/테이블)에 정확히 맞진 않지만 다양성 우선.
나중에 부족하면 책상/카페 위주 데이터 추가 가능.

다운로드 한 번만 (1GB). 이미 있으면 건너뜀.
"""

from __future__ import annotations
import argparse
import hashlib
import os
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

OUT_DIR = Path(__file__).parent / "data" / "backgrounds"
COCO_VAL_URL = "http://images.cocodataset.org/zips/val2017.zip"
COCO_VAL_SHA256 = ""  # 공식 미공개 — 크기로만 sanity check
EXPECTED_MIN_BYTES = 700_000_000  # 700MB 이상이면 정상

UA = "PokeFolioCardDetectorTraining/0.1"


def download_with_progress(url: str, dst: Path) -> None:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req) as resp:
        total = int(resp.headers.get("Content-Length", 0))
        chunk = 1024 * 256
        downloaded = 0
        last_pct = -1
        with open(dst, "wb") as f:
            while True:
                buf = resp.read(chunk)
                if not buf:
                    break
                f.write(buf)
                downloaded += len(buf)
                if total > 0:
                    pct = int(downloaded * 100 / total)
                    if pct != last_pct and pct % 5 == 0:
                        print(f"  {pct:3d}% ({downloaded / 1e6:.0f}MB / {total / 1e6:.0f}MB)")
                        last_pct = pct


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--keep-zip", action="store_true",
                        help="추출 후 zip 파일 삭제 안 함")
    parser.add_argument("--max", type=int, default=5000,
                        help="압축 해제할 최대 이미지 수 (기본 전체)")
    args = parser.parse_args()

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    existing = list(OUT_DIR.glob("*.jpg"))
    if len(existing) >= args.max * 0.9:
        print(f"이미 {len(existing)}장 있음 — 건너뜀.")
        return 0

    with tempfile.TemporaryDirectory() as tmp:
        zip_path = Path(tmp) / "val2017.zip"
        print(f"COCO val2017 다운로드 → {zip_path}")
        download_with_progress(COCO_VAL_URL, zip_path)

        size = zip_path.stat().st_size
        if size < EXPECTED_MIN_BYTES:
            print(f"경고: 다운로드 크기 {size:,} bytes — 손상 가능. 재시도 권장.",
                  file=sys.stderr)
            return 1

        print(f"압축 해제 → {OUT_DIR}")
        with zipfile.ZipFile(zip_path) as zf:
            members = [m for m in zf.namelist() if m.endswith(".jpg")]
            members = members[: args.max]
            for i, name in enumerate(members):
                # 폴더 구조 무시, 파일명만
                base = os.path.basename(name)
                if not base:
                    continue
                with zf.open(name) as src, open(OUT_DIR / base, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                if (i + 1) % 500 == 0:
                    print(f"  {i + 1}/{len(members)}")

        if args.keep_zip:
            shutil.copy(zip_path, OUT_DIR.parent / "val2017.zip")

    final = list(OUT_DIR.glob("*.jpg"))
    print(f"\n완료 — {len(final)}장 배경 이미지 준비됨.")
    print(f"폴더: {OUT_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
