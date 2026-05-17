# Scanner Card Detector — YOLOv8 Training Pipeline

`scanner/main.py`의 detect 단계를 OpenCV contour에서 **카드 전용 YOLOv8n**으로 교체하기 위한 학습 파이프라인.

## 왜 필요한가

현재 OpenCV `_detect_card_corners`는 "사각형 모양"만 본다. 문/책/액자/쌀자루도 카드라고 false positive. 진짜 "포켓몬 카드" 의미를 학습한 객체탐지 모델이 필요.

2단계 분리:
1. **detect** (이 영역이 카드인가?) — 이 작업이 다루는 부분
2. **identify** (그래서 어떤 카드인가?) — 이미 DINOv2 + FAISS로 동작 중

## 파이프라인

```
scanner/training/
├── crawl_eval_set.py        # Reddit r/pokemoncards 등에서 실물 사진 자동 수집
├── build_dataset.py         # 합성 학습 데이터 생성 (reference × 배경 × 변환)
├── train_yolo.py            # Ultralytics YOLOv8n 학습 (M2 MPS)
├── evaluate.py              # eval 셋으로 mAP 측정
├── requirements.txt
└── data/
    ├── raw_eval/            # 크롤러 1차 다운로드
    ├── eval/                # 검수 통과한 평가셋
    ├── backgrounds/         # COCO subset (합성 배경)
    └── synthetic/           # build_dataset.py 출력 (train/val)
```

## 빠른 시작

```bash
# 1. 환경 셋업 (scanner_v2 conda env 가정)
cd scanner/training
source /Users/fury/miniconda3/envs/scanner_v2/bin/activate
pip install -r requirements.txt

# 2. eval 셋 수집 (사용자: 다운로드 끝나면 data/raw_eval/ 폴더 열어서 카드 아닌 사진 솎아내기)
python crawl_eval_set.py --target 300

# 3. 배경 다운로드 (COCO 2017 val subset ~1GB)
python download_backgrounds.py

# 4. 합성 학습 데이터 생성
python build_dataset.py --samples 50000

# 5. 학습 (M2 Mac MPS 기준 2~4시간)
python train_yolo.py --epochs 50

# 6. 평가
python evaluate.py --weights runs/detect/train/weights/best.pt

# 7. 통합 — scanner/main.py 수정 (자동)
python integrate.py
```

## 데이터 규모 가이드

- **Reference cards** (이미 있음): `scanner/data/cards/` 15,760장
- **합성 학습 데이터**: 50,000장 (reference × 배경 × 변환 조합)
- **Eval 셋**: 200~500장 (실제 카메라 사진)

## 학습 후

- `runs/detect/train/weights/best.pt` 생성
- `scanner/main.py`의 `_detect_card_corners` 함수가 이걸 사용하도록 교체
- 프론트/백엔드 인터페이스 변경 없음 (corners 정규화 4점 반환)
