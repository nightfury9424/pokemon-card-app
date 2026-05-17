"""합성 학습 데이터 생성기.

reference 카드 (scanner/data/cards/*.jpg + .png) × 배경 (COCO val) × 변환 →
YOLOv8 OBB(oriented bounding box) format 학습 데이터.

OBB를 쓰는 이유: 카드가 기울어진 perspective에서도 4-corner 정확히 학습.
일반 axis-aligned bbox는 회전된 카드를 큰 사각형으로 묶어 정밀도 ↓.

출력 구조 (Ultralytics 표준):
  data/synthetic/
    ├── images/
    │   ├── train/{idx:06d}.jpg
    │   └── val/{idx:06d}.jpg
    └── labels/
        ├── train/{idx:06d}.txt   # "0 x1 y1 x2 y2 x3 y3 x4 y4" (정규화)
        └── val/{idx:06d}.txt
  data.yaml                       # Ultralytics 학습 config

변환 종류:
  - 회전 (-45~45°)
  - 스케일 (배경의 12~55%)
  - perspective (4점 무작위 변위 ~8%)
  - brightness/contrast/saturation
  - blur (모션 블러 약간)
  - holo glare 시뮬레이션 (대각 밝은 띠)
  - sleeve reflection (윗부분 흐림 + 흰 반사선)
  - 부분 occlusion (검은 사각형 — 손가락 가림 시뮬)
"""

from __future__ import annotations
import argparse
import math
import multiprocessing as mp
import random
import sys
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np
from tqdm import tqdm

ROOT = Path(__file__).parent
CARDS_DIR = ROOT.parent / "data" / "cards"
BG_DIR = ROOT / "data" / "backgrounds"
OUT_DIR = ROOT / "data" / "synthetic"


def list_card_images() -> list[Path]:
    paths = sorted(CARDS_DIR.glob("*.jpg")) + sorted(CARDS_DIR.glob("*.png"))
    return [p for p in paths if p.stat().st_size > 5_000]  # 빈 파일 제외


def list_backgrounds() -> list[Path]:
    return sorted(BG_DIR.glob("*.jpg"))


def load_card(path: Path) -> np.ndarray | None:
    img = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if img is None:
        return None
    # alpha 채널 없으면 추가 (전체 불투명)
    if img.ndim == 2:
        img = cv2.cvtColor(img, cv2.COLOR_GRAY2BGRA)
    elif img.shape[2] == 3:
        img = cv2.cvtColor(img, cv2.COLOR_BGR2BGRA)
    return img


def random_perspective_warp(
    card: np.ndarray, max_scale: float, min_scale: float, bg_size: tuple[int, int]
) -> tuple[np.ndarray, np.ndarray]:
    """카드를 무작위 perspective + scale + rotation. 변환된 카드와 4-corner 좌표 반환."""
    h, w = card.shape[:2]
    bg_h, bg_w = bg_size

    # 목표 스케일 — 배경의 짧은 변 기준
    target_short = random.uniform(min_scale, max_scale) * min(bg_h, bg_w)
    if h >= w:
        target_h = target_short
        target_w = target_h * (w / h)
    else:
        target_w = target_short
        target_h = target_w * (h / w)

    # 회전 각도 (대부분 ±25° 안, 가끔 큰 회전)
    if random.random() < 0.08:
        angle = random.uniform(-90, 90)
    else:
        angle = random.uniform(-25, 25)
    rad = math.radians(angle)
    cos, sin = math.cos(rad), math.sin(rad)

    # 원본 카드의 4점 (centered at 0)
    cx, cy = w / 2, h / 2
    src_corners = np.array(
        [[0, 0], [w, 0], [w, h], [0, h]], dtype=np.float32
    )

    # scale + rotate + perspective jitter
    scale_x = target_w / w
    scale_y = target_h / h

    # perspective 변위 — 각 코너에 약간의 무작위 이동
    persp_amt = 0.06 if random.random() < 0.7 else 0.12
    jitter = np.random.uniform(-persp_amt, persp_amt, (4, 2)) * np.array([target_w, target_h])

    # 1. scale around center
    scaled = (src_corners - [cx, cy]) * [scale_x, scale_y]
    # 2. rotate
    rot_mat = np.array([[cos, -sin], [sin, cos]])
    rotated = scaled @ rot_mat.T
    # 3. perspective jitter
    jittered = rotated + jitter

    # 4. 배경 안에 들어가도록 위치 정함 — 약간 여백 두고 random
    margin = 12
    min_x, min_y = jittered.min(axis=0)
    max_x, max_y = jittered.max(axis=0)
    span_x = max_x - min_x
    span_y = max_y - min_y
    if span_x >= bg_w - 2 * margin or span_y >= bg_h - 2 * margin:
        # 너무 큼 — 비율 줄임
        shrink = min((bg_w - 2 * margin) / span_x, (bg_h - 2 * margin) / span_y) * 0.9
        jittered *= shrink
        min_x, min_y = jittered.min(axis=0)
        max_x, max_y = jittered.max(axis=0)
        span_x = max_x - min_x
        span_y = max_y - min_y
    tx = random.uniform(margin - min_x, bg_w - margin - max_x)
    ty = random.uniform(margin - min_y, bg_h - margin - max_y)
    dst_corners = jittered + [tx, ty]

    # 5. perspective transform matrix (src → dst)
    M = cv2.getPerspectiveTransform(src_corners, dst_corners.astype(np.float32))
    warped = cv2.warpPerspective(
        card, M, (bg_w, bg_h), borderMode=cv2.BORDER_CONSTANT, borderValue=(0, 0, 0, 0)
    )
    return warped, dst_corners.astype(np.float32)


def jitter_color(card_bgra: np.ndarray) -> np.ndarray:
    """카드 BGR 채널만 색감 변화. alpha는 유지."""
    bgr = card_bgra[..., :3]
    a = card_bgra[..., 3:]
    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV).astype(np.int16)
    hsv[..., 0] = (hsv[..., 0] + random.randint(-8, 8)) % 180
    hsv[..., 1] = np.clip(hsv[..., 1] * random.uniform(0.7, 1.2), 0, 255)
    hsv[..., 2] = np.clip(hsv[..., 2] * random.uniform(0.65, 1.25) + random.randint(-12, 12), 0, 255)
    bgr2 = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)
    return np.dstack([bgr2, a])


def add_holo_glare(card_bgra: np.ndarray) -> np.ndarray:
    """대각선 밝은 띠 — 홀로/포일 카드의 빛 반사 시뮬."""
    h, w = card_bgra.shape[:2]
    overlay = np.zeros((h, w), np.float32)
    cx = random.uniform(0.2, 0.8) * w
    angle = random.uniform(-30, 30)
    thick = random.uniform(0.15, 0.35) * min(h, w)
    cos, sin = math.cos(math.radians(angle)), math.sin(math.radians(angle))
    yy, xx = np.mgrid[0:h, 0:w]
    dist = np.abs((xx - cx) * cos + (yy - h / 2) * sin)
    overlay = np.clip(1.0 - dist / thick, 0, 1)
    overlay = (overlay * random.uniform(80, 180)).astype(np.int16)
    bgr = card_bgra[..., :3].astype(np.int16)
    bgr += overlay[..., None]
    bgr = np.clip(bgr, 0, 255).astype(np.uint8)
    return np.dstack([bgr, card_bgra[..., 3]])


def add_sleeve_reflection(card_bgra: np.ndarray) -> np.ndarray:
    """슬리브의 윗부분 흰 반사 띠 + 살짝 흐림."""
    h, w = card_bgra.shape[:2]
    band_h = int(h * random.uniform(0.06, 0.2))
    top_band = card_bgra[:band_h, :, :3].astype(np.int16)
    top_band += random.randint(40, 100)
    card_bgra[:band_h, :, :3] = np.clip(top_band, 0, 255).astype(np.uint8)
    # 약한 가우시안 블러 (전체)
    if random.random() < 0.5:
        bgr_blur = cv2.GaussianBlur(card_bgra[..., :3], (3, 3), 0)
        card_bgra = np.dstack([bgr_blur, card_bgra[..., 3]])
    return card_bgra


def add_occlusion(out_bgr: np.ndarray, corners: np.ndarray) -> None:
    """카드 일부를 검은/피부색 사각형으로 가림 (손가락 시뮬)."""
    cx, cy = corners.mean(axis=0)
    w_card = np.linalg.norm(corners[1] - corners[0])
    block_w = int(w_card * random.uniform(0.08, 0.18))
    block_h = int(w_card * random.uniform(0.15, 0.35))
    angle = math.atan2(corners[1][1] - corners[0][1], corners[1][0] - corners[0][0])
    # 카드 가장자리 근처에서 시작 — 안쪽으로 진입
    side = random.choice([0, 1, 2, 3])
    p1 = corners[side]
    p2 = corners[(side + 1) % 4]
    t = random.uniform(0.2, 0.8)
    anchor = p1 + (p2 - p1) * t
    # 무작위 색 — 어두운 톤 또는 피부색
    color = random.choice([
        (40, 40, 40),
        (60, 100, 160),  # 살색 톤
        (90, 120, 180),
        (20, 20, 20),
    ])
    box = np.array([
        [-block_w / 2, -block_h / 2],
        [block_w / 2, -block_h / 2],
        [block_w / 2, block_h / 2],
        [-block_w / 2, block_h / 2],
    ])
    rot = np.array([[math.cos(angle), -math.sin(angle)], [math.sin(angle), math.cos(angle)]])
    box = box @ rot.T + anchor
    cv2.fillPoly(out_bgr, [box.astype(np.int32)], color)


def composite(card_warped: np.ndarray, bg: np.ndarray) -> np.ndarray:
    """alpha 블렌딩 — card 위에 bg."""
    a = card_warped[..., 3:].astype(np.float32) / 255.0
    blend = card_warped[..., :3].astype(np.float32) * a + bg.astype(np.float32) * (1 - a)
    return blend.astype(np.uint8)


def write_label(label_path: Path, corners: np.ndarray, bg_w: int, bg_h: int) -> None:
    """YOLOv8 OBB format: class x1 y1 x2 y2 x3 y3 x4 y4 (정규화)."""
    norm = corners.copy()
    norm[:, 0] /= bg_w
    norm[:, 1] /= bg_h
    norm = np.clip(norm, 0.0, 1.0)
    line = "0 " + " ".join(f"{v:.6f}" for v in norm.flatten())
    label_path.write_text(line + "\n")


def synth_one(args: tuple[Path, Path, Path, Path, int]) -> bool:
    card_path, bg_path, img_out, lbl_out, seed = args
    rnd = random.Random(seed)
    random.seed(seed)
    np.random.seed(seed)
    try:
        card = load_card(card_path)
        if card is None:
            return False
        bg = cv2.imread(str(bg_path))
        if bg is None:
            return False
        bg_h, bg_w = bg.shape[:2]
        # 배경이 너무 작으면 늘림
        if min(bg_h, bg_w) < 480:
            s = 480 / min(bg_h, bg_w)
            bg = cv2.resize(bg, (int(bg_w * s), int(bg_h * s)))
            bg_h, bg_w = bg.shape[:2]

        # 카드 변환 (BGRA 유지)
        if rnd.random() < 0.5:
            card = jitter_color(card)
        if rnd.random() < 0.35:
            card = add_holo_glare(card)
        if rnd.random() < 0.25:
            card = add_sleeve_reflection(card)

        warped, corners = random_perspective_warp(
            card, max_scale=0.55, min_scale=0.12, bg_size=(bg_h, bg_w)
        )

        out = composite(warped, bg)
        if rnd.random() < 0.18:
            add_occlusion(out, corners)
        # 모션 블러 약간
        if rnd.random() < 0.1:
            k = rnd.choice([3, 5])
            out = cv2.GaussianBlur(out, (k, k), 0)

        cv2.imwrite(str(img_out), out, [cv2.IMWRITE_JPEG_QUALITY, 88])
        write_label(lbl_out, corners, bg_w, bg_h)
        return True
    except Exception as e:  # noqa: BLE001
        print(f"err on {card_path.name} × {bg_path.name}: {e}", file=sys.stderr)
        return False


def write_yaml(out_root: Path) -> None:
    """Ultralytics data.yaml — OBB 학습 config."""
    yaml = f"""# 자동 생성 — build_dataset.py
path: {out_root.resolve()}
train: images/train
val: images/val
names:
  0: pokemon_card
"""
    (out_root / "data.yaml").write_text(yaml)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=20000, help="총 합성 샘플 수")
    parser.add_argument("--val-ratio", type=float, default=0.08)
    parser.add_argument("--workers", type=int, default=mp.cpu_count() - 1)
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    cards = list_card_images()
    bgs = list_backgrounds()
    if not cards:
        print(f"카드 이미지 없음: {CARDS_DIR}", file=sys.stderr)
        return 1
    if not bgs:
        print(f"배경 이미지 없음: {BG_DIR} — download_backgrounds.py 먼저 실행", file=sys.stderr)
        return 1

    print(f"카드 {len(cards)}장, 배경 {len(bgs)}장 로드.")

    # 출력 폴더
    for split in ("train", "val"):
        (OUT_DIR / "images" / split).mkdir(parents=True, exist_ok=True)
        (OUT_DIR / "labels" / split).mkdir(parents=True, exist_ok=True)

    random.seed(args.seed)
    n_val = int(args.samples * args.val_ratio)
    n_train = args.samples - n_val

    jobs = []
    for split, n in (("train", n_train), ("val", n_val)):
        for i in range(n):
            card = random.choice(cards)
            bg = random.choice(bgs)
            img_out = OUT_DIR / "images" / split / f"{i:06d}.jpg"
            lbl_out = OUT_DIR / "labels" / split / f"{i:06d}.txt"
            jobs.append((card, bg, img_out, lbl_out, args.seed + i + (1 if split == "val" else 0) * 10_000_000))

    print(f"생성 중 — train {n_train}, val {n_val}, workers {args.workers}")
    ok = 0
    with ProcessPoolExecutor(max_workers=args.workers) as pool:
        futures = [pool.submit(synth_one, job) for job in jobs]
        with tqdm(total=len(futures)) as bar:
            for f in as_completed(futures):
                if f.result():
                    ok += 1
                bar.update(1)

    write_yaml(OUT_DIR)
    print(f"\n완료 — {ok}/{len(jobs)} 생성됨.")
    print(f"data.yaml: {OUT_DIR / 'data.yaml'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
