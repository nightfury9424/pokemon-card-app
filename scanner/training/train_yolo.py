"""YOLOv8n-OBB 학습 wrapper.

Ultralytics 라이브러리 사용. Apple Silicon MPS 자동 감지.
build_dataset.py가 만든 data/synthetic/data.yaml 사용.

기본 설정:
  - 모델: yolov8n-obb (nano, OBB) — CPU/MPS 30~50ms 추론
  - epochs: 50
  - imgsz: 640
  - batch: 16 (MPS 메모리에 맞춰 조정)
"""

from __future__ import annotations
import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).parent
DATA_YAML = ROOT / "data" / "synthetic" / "data.yaml"
RUNS_DIR = ROOT / "runs"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", default="yolov8n-obb.pt",
                        help="기반 모델 — 더 큰 정확도 원하면 yolov8s-obb.pt")
    parser.add_argument("--epochs", type=int, default=50)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=16)
    parser.add_argument("--data", default=str(DATA_YAML))
    parser.add_argument("--device", default="mps",
                        help="mps (Apple Silicon GPU) / cpu / cuda")
    parser.add_argument("--resume", action="store_true")
    args = parser.parse_args()

    if not Path(args.data).exists():
        print(f"data.yaml 없음: {args.data}", file=sys.stderr)
        print("→ build_dataset.py 먼저 실행", file=sys.stderr)
        return 1

    try:
        from ultralytics import YOLO
    except ImportError:
        print("ultralytics 미설치 — pip install ultralytics", file=sys.stderr)
        return 1

    RUNS_DIR.mkdir(parents=True, exist_ok=True)

    print(f"모델 로드: {args.model}")
    model = YOLO(args.model)

    print(f"학습 시작 — device={args.device}, epochs={args.epochs}, imgsz={args.imgsz}")
    model.train(
        data=args.data,
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        project=str(RUNS_DIR / "detect"),
        name="train",
        exist_ok=True,
        # 일반 augmentation은 비활성 — 합성 단계에서 이미 적용했으니 중복 방지
        hsv_h=0.0,
        hsv_s=0.0,
        hsv_v=0.0,
        degrees=0.0,
        translate=0.0,
        scale=0.0,
        shear=0.0,
        perspective=0.0,
        flipud=0.0,
        fliplr=0.5,  # 좌우 flip만 약간 (대칭 카드)
        mosaic=0.0,
        mixup=0.0,
        resume=args.resume,
    )

    print("\n완료. weights 경로:")
    print(f"  {RUNS_DIR / 'detect' / 'train' / 'weights' / 'best.pt'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
