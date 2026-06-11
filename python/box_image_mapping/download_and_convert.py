"""
Phase B.1 — CSV 의 confirmed/manual 항목 이미지 다운로드 + WebP 변환.

입력: 사용자 export CSV (product_image_mapping_confirmed_*.csv)
출력: python/box_image_mapping/boxes/{product_id}.webp

WebP 옵션:
  quality 85 — 시각 품질 vs 파일 크기 균형
  method 6  — 최대 압축 (속도 trade-off OK, 1회성 ETL)

원본 이미지 = 한국 포켓몬 공식 제품 썸네일.
S3 boxes/v1/ 패턴 따름 — 다음 Step 에서 업로드.

실행:
  /Users/fury/miniconda3/envs/scanner_v2/bin/python download_and_convert.py \\
    --csv /path/to/product_image_mapping_confirmed_*.csv
"""

from __future__ import annotations
import argparse
import csv
import sys
import time
import urllib.request
from io import BytesIO
from pathlib import Path

from PIL import Image

HERE = Path(__file__).parent
BOXES = HERE / "boxes"
BOXES.mkdir(exist_ok=True)

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"


def download(url: str, timeout: int = 15) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return resp.read()


def convert_to_webp(data: bytes, out_path: Path) -> tuple[int, int, int]:
    """원본 → RGB → WebP. 반환: (input_bytes, output_bytes, w*h)."""
    img = Image.open(BytesIO(data))
    if img.mode in ("RGBA", "LA", "P"):
        # WebP 도 alpha 지원하지만 박스 표지에 alpha 필요 X.
        # 흰 배경 합성 (사이트 PNG 가 transparent 인 경우 깔끔).
        bg = Image.new("RGB", img.size, (255, 255, 255))
        if img.mode == "RGBA" or img.mode == "LA":
            bg.paste(img, mask=img.split()[-1])
        else:
            bg.paste(img.convert("RGBA"), mask=img.convert("RGBA").split()[-1])
        img = bg
    elif img.mode != "RGB":
        img = img.convert("RGB")

    buf = BytesIO()
    img.save(buf, format="WEBP", quality=85, method=6)
    out_path.write_bytes(buf.getvalue())
    return len(data), len(buf.getvalue()), img.size[0] * img.size[1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True, help="confirmed CSV path")
    args = ap.parse_args()

    csv_path = Path(args.csv).expanduser().resolve()
    if not csv_path.exists():
        print(f"[err] CSV 없음: {csv_path}", file=sys.stderr)
        return 1

    rows = list(csv.DictReader(csv_path.open(encoding="utf-8")))
    target = [r for r in rows if r["action"] in ("confirmed", "manual") and r["image_url"]]
    print(f"[start] {len(target)} 이미지 처리 (총 row {len(rows)})", file=sys.stderr)

    ok, fail = 0, 0
    total_in, total_out = 0, 0
    t0 = time.time()

    for i, r in enumerate(target, 1):
        pid = r["product_id"]
        url = r["image_url"]
        name = r["db_name"]
        out_path = BOXES / f"{pid}.webp"

        if out_path.exists():
            print(f"  [{i:3}/{len(target)}] skip (이미 있음) {pid}", file=sys.stderr)
            ok += 1
            continue

        try:
            data = download(url)
            in_bytes, out_bytes, _ = convert_to_webp(data, out_path)
            total_in += in_bytes
            total_out += out_bytes
            ratio = 100 * (1 - out_bytes / in_bytes) if in_bytes else 0
            print(f"  [{i:3}/{len(target)}] ok {pid}  {in_bytes/1024:.0f}KB → {out_bytes/1024:.0f}KB "
                  f"(-{ratio:.0f}%)  {name[:30]}", file=sys.stderr)
            ok += 1
            time.sleep(0.05)  # 가볍게 rate-limit (사이트 부담 X)
        except Exception as e:
            print(f"  [{i:3}/{len(target)}] FAIL {pid}  {e}", file=sys.stderr)
            fail += 1

    elapsed = time.time() - t0
    print(f"\n[done] ok {ok} / fail {fail} / {elapsed:.1f}s", file=sys.stderr)
    if total_in:
        print(f"       total {total_in/1024:.0f}KB → {total_out/1024:.0f}KB "
              f"(-{100*(1-total_out/total_in):.0f}%)", file=sys.stderr)
    print(f"       out dir: {BOXES}", file=sys.stderr)
    return 0 if fail == 0 else 2


if __name__ == "__main__":
    sys.exit(main())
