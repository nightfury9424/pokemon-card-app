"""Reddit r/pokemoncards 등에서 실물 카드 사진을 자동 수집해 평가셋 후보로 저장.

- PRAW 인증 없이 reddit public JSON endpoint 사용 (User-Agent만 설정).
- 다운로드 후 자동 필터: 해상도/aspect ratio + 기존 OpenCV detect로 "단일 카드" 후보만 통과.
- 통과한 이미지는 data/raw_eval/{subreddit}_{post_id}.jpg
- 라벨링은 별도 단계 (Roboflow 같은 툴) — 이 스크립트는 raw 수집만.

크롤링 대상 서브레딧 우선순위:
  r/pokemoncards   (가장 활발, 단일 카드 자랑 글 많음)
  r/PokeInvesting  (시세 사진 — 카드 단독)
  r/PokeTCG        (덱 사진 → 단일 카드 적음, 필터로 제거)
"""

from __future__ import annotations
import argparse
import json
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path
from typing import Iterable

# scanner 루트 import 가능하도록
SCANNER_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCANNER_ROOT))

import cv2  # noqa: E402
import numpy as np  # noqa: E402

OUT_DIR = Path(__file__).parent / "data" / "raw_eval"
OUT_DIR.mkdir(parents=True, exist_ok=True)

UA = "PokeFolioCardDetectorEval/0.1 (research; non-commercial)"
SUBREDDITS = (
    "pokemoncards",
    "PokeInvesting",
    "PokemonTCG",
    "pkmntcgcollections",
    "PokemonTCGDeals",
)
SORTS = ("top", "hot", "new")
TIMES = ("year", "month", "week")


def fetch_listing(subreddit: str, sort: str, t: str, limit: int = 100) -> list[dict]:
    url = f"https://www.reddit.com/r/{subreddit}/{sort}.json?t={t}&limit={limit}"
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"  HTTPError {e.code} on {subreddit}/{sort}/{t}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"  err on {subreddit}/{sort}/{t}: {e}", file=sys.stderr)
        return []
    return [c["data"] for c in data.get("data", {}).get("children", [])]


def post_image_urls(post: dict) -> Iterable[str]:
    # 단일 이미지 우선. 갤러리 글은 첫 장만 (단일 카드 가정).
    url = post.get("url", "")
    if any(url.lower().endswith(s) for s in (".jpg", ".jpeg", ".png")):
        yield url
        return
    # i.redd.it 이미지 호스팅
    if "i.redd.it" in url:
        yield url
        return
    # preview 이미지 (gallery 또는 link)
    preview = post.get("preview", {}).get("images", [])
    if preview:
        src = preview[0].get("source", {}).get("url", "")
        if src:
            yield src.replace("&amp;", "&")


def download(url: str, dst: Path) -> bool:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = resp.read()
    except Exception as e:
        print(f"  download failed: {e}", file=sys.stderr)
        return False
    dst.write_bytes(data)
    return True


def passes_filter(img_path: Path) -> tuple[bool, str]:
    """단일 카드 후보 가능성 1차 필터 (느슨한 버전).

    엄격한 검수는 사용자 수동 단계로 미룸 — 자동은 명백한 쓰레기(너무 작거나 다중 카드만)
    만 컷.
    - 해상도 너무 작은 거 제외 (< 300px shorter side)
    - aspect는 휴대폰 세로 스크린샷 포함 (0.3~3.0)
    - OpenCV CardDetector는 보조 신호로만 — 잡으면 통과, 못 잡아도 통과(단독 카드 사진은
      자주 못 잡힘. 사용자 수동 검수에서 처리).
    """
    img = cv2.imread(str(img_path))
    if img is None:
        return False, "decode_fail"
    h, w = img.shape[:2]
    if min(h, w) < 300:
        return False, f"too_small({w}x{h})"
    ratio_img = w / h
    if not (0.3 < ratio_img < 3.0):
        return False, f"odd_aspect({w}x{h})"
    return True, "ok"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, default=300, help="필터 통과 목표 장수")
    parser.add_argument("--limit-per-listing", type=int, default=100)
    args = parser.parse_args()

    seen_ids: set[str] = {p.stem.split("_", 1)[1] for p in OUT_DIR.glob("*.jpg")
                          if "_" in p.stem}
    passed = sum(1 for _ in OUT_DIR.glob("*.jpg"))
    print(f"이미 다운로드된 통과 이미지: {passed}장 (목표 {args.target})")

    for sub in SUBREDDITS:
        for sort in SORTS:
            for t in TIMES:
                if passed >= args.target:
                    break
                print(f"[{sub}/{sort}/{t}] fetching listing...")
                posts = fetch_listing(sub, sort, t, limit=args.limit_per_listing)
                print(f"  {len(posts)} posts")
                for post in posts:
                    if passed >= args.target:
                        break
                    pid = post.get("id", "")
                    if not pid or pid in seen_ids:
                        continue
                    for url in post_image_urls(post):
                        ext = url.rsplit(".", 1)[-1].split("?")[0].lower()
                        if ext not in ("jpg", "jpeg", "png"):
                            ext = "jpg"
                        tmp = OUT_DIR / f"_tmp_{sub}_{pid}.{ext}"
                        if not download(url, tmp):
                            break
                        ok, reason = passes_filter(tmp)
                        if ok:
                            final = OUT_DIR / f"{sub}_{pid}.jpg"
                            # PNG → JPG 변환 (저장 일관)
                            if ext != "jpg":
                                img = cv2.imread(str(tmp))
                                if img is not None:
                                    cv2.imwrite(str(final), img,
                                                [cv2.IMWRITE_JPEG_QUALITY, 92])
                                tmp.unlink(missing_ok=True)
                            else:
                                tmp.rename(final)
                            seen_ids.add(pid)
                            passed += 1
                            print(f"  ✓ {sub}_{pid} ({passed}/{args.target})")
                        else:
                            tmp.unlink(missing_ok=True)
                            print(f"  ✗ {sub}_{pid}: {reason}")
                        time.sleep(0.5)  # 짧은 휴식
                        break  # 한 게시물에서 첫 이미지만
                time.sleep(2)  # listing 간 휴식

    print(f"\n완료 — {passed}장 통과")
    print(f"폴더: {OUT_DIR}")
    print("\n다음 단계:")
    print("  1. 폴더 열어서 카드 아닌 사진 (덱 사진/박스 사진 등) 직접 삭제")
    print("  2. 남은 사진들을 data/eval/ 로 이동 (또는 Roboflow에 업로드해 bbox 라벨링)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
