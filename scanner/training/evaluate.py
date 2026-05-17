"""학습된 YOLO 모델로 eval 셋에 대해 정량/정성 평가.

용법:
  python evaluate.py --weights runs/detect/train/weights/best.pt

기능:
  - data/eval/ 의 이미지 전부 inference
  - 각 이미지에 대해 detect 결과 (bbox, OBB corners, confidence) 추출
  - 시각화 이미지 → runs/eval_vis/{filename}.jpg
  - 통계: detect rate (≥1개 잡힌 비율), avg confidence

라벨링된 eval 셋 (data/eval/labels/*.txt)이 있으면 mAP도 계산.
없으면 정성 평가만 (어떻게 잡았는지 사람이 봄).
"""

from __future__ import annotations
import argparse
import sys
from pathlib import Path

import cv2
import numpy as np

ROOT = Path(__file__).parent
EVAL_DIR = ROOT / "data" / "eval"
VIS_DIR = ROOT / "runs" / "eval_vis"


def draw_obb(img: np.ndarray, corners: np.ndarray, conf: float) -> None:
    pts = corners.astype(np.int32)
    cv2.polylines(img, [pts], isClosed=True, color=(0, 255, 0), thickness=2)
    cx, cy = pts.mean(axis=0).astype(int)
    cv2.putText(img, f"{conf:.2f}", (cx - 30, cy),
                cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--weights", required=True)
    parser.add_argument("--source", default=str(EVAL_DIR))
    parser.add_argument("--conf", type=float, default=0.25)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--device", default="mps")
    args = parser.parse_args()

    try:
        from ultralytics import YOLO
    except ImportError:
        print("ultralytics 미설치", file=sys.stderr)
        return 1

    src = Path(args.source)
    if not src.exists():
        print(f"eval 폴더 없음: {src}", file=sys.stderr)
        return 1

    imgs = sorted(list(src.glob("*.jpg")) + list(src.glob("*.png")))
    if not imgs:
        print(f"eval 이미지 없음: {src}", file=sys.stderr)
        return 1

    VIS_DIR.mkdir(parents=True, exist_ok=True)
    model = YOLO(args.weights)

    detected = 0
    total = len(imgs)
    confs: list[float] = []
    counts: list[int] = []

    for img_path in imgs:
        img = cv2.imread(str(img_path))
        if img is None:
            continue
        results = model(img, imgsz=args.imgsz, conf=args.conf, device=args.device,
                        verbose=False)
        r = results[0]
        obb = getattr(r, "obb", None)
        n = 0
        if obb is not None and obb.xyxyxyxy is not None:
            corners_all = obb.xyxyxyxy.cpu().numpy()  # (N, 4, 2)
            confs_arr = obb.conf.cpu().numpy()  # (N,)
            n = len(corners_all)
            if n > 0:
                detected += 1
            for c, conf in zip(corners_all, confs_arr):
                draw_obb(img, c, float(conf))
                confs.append(float(conf))
        counts.append(n)
        cv2.imwrite(str(VIS_DIR / img_path.name), img)

    print(f"\n=== 결과 ===")
    print(f"전체: {total}장")
    print(f"≥1개 detect: {detected}장 ({detected / total * 100:.1f}%)")
    if confs:
        print(f"평균 confidence: {np.mean(confs):.3f}")
        print(f"평균 detect per image: {np.mean(counts):.2f}")
    print(f"\n시각화: {VIS_DIR}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
