# 카드 스캐너 고도화 개발 문서 v2

> 현재 Ollama llava 방식의 한계를 극복하기 위한 DINOv2 + FAISS 기반 스캐너 고도화 계획

---

## 현재 방식의 한계 (Ollama llava)

| 문제 | 내용 |
|------|------|
| 속도 | 첫 호출 시 모델 로딩 10~20초 소요 |
| 의존성 | Ollama 서버가 항상 실행되어 있어야 함 |
| 정확도 | 홀로그램/반사 카드에서 수록번호 오인식 |
| 확장성 | 외부 API 의존 → 스캔 제한 생길 수 있음 |

---

## 새로운 방식: DINOv2 + FAISS

### 왜 DINOv2인가?
- CLIP보다 세밀한 이미지 차이 구별에 강함
- 포켓몬 카드처럼 비슷한 이미지들 사이 구별에 최적화
- 파인튜닝 후 홀로그램/반사 노이즈에도 강인해짐
- Apple MPS (M2/M4) 에서 충분히 돌아가는 크기
- 학습 없이 분류 레이어 불필요 → 새 카드 추가 시 DB만 업데이트하면 됨

### 전체 파이프라인
```
카드 사진 입력
    → 카드 영역 감지 (OpenCV 컨투어)
    → DINOv2 임베딩 추출
    → FAISS 유사도 검색 (Top-5)
    → card_id 기준으로 카드 정보 반환
    → Spring Boot → Flutter 모달
```

---

## 대상 카드 범위

RR(더블레어) 이상 ~ 프로모까지

| 레어도 | 설명 | 홀로 처리 |
|--------|------|----------|
| RR | ex, GX, V 카드 | ✅ |
| RRR | VMAX, VSTAR | ✅ |
| SR | 박스당 0~1장 | ✅ |
| AR | 풀프레임 일러스트 | ✅ |
| SAR | 특수 일러스트 | ✅ |
| HR | 무지개 배경 | ✅ |
| UR | 전체 금색 | ✅ |
| SSR | 이로치 포켓몬 | ✅ |
| CHR | 트레이너와 함께 | ✅ |
| CSR | 트레이너와 함께 (V/VMAX) | ✅ |
| ACE | 에이스 스펙 | ✅ |
| 프로모 | 대회/이벤트 한정 | ✅ |

- C/U (커먼/언커먼) 제외 → 홀로 없고 가치 낮음
- RR 이상은 전부 홀로 처리 → 실사 이미지 학습이 필수

---

## 언어판 처리 방침

### KO / EN / JP = 같은 카드로 취급
- 일러스트가 동일하기 때문
- 언어판마다 이미지가 달라 자연스러운 positive pair 역할
- FAISS 검색 결과가 어떤 언어판이든 동일한 card_id로 매핑

```
card_id (언어 무관)
    ├── KO 이미지 임베딩  ──┐
    ├── EN 이미지 임베딩  ──┤ → 전부 같은 카드로 매핑
    └── JP 이미지 임베딩  ──┘
```

---

## 데이터 수집 전략

### 3단계 데이터 파이프라인

```
1단계: TCG API 이미지 (KO/EN/JP)
    - 베이스 데이터, 자동 수집 가능
    - 스튜디오 컷이라 실사와 차이 있음
    - 카드당 최대 3장

2단계: 실사 이미지 크롤링
    - 실제 사용자가 찍은 이미지
    - 이미 카드 정보와 매핑되어 있음 (상품 페이지)
    - 홀로그램/조명/각도 다양성 확보
    - 초기 인식률을 크게 끌어올리는 핵심

3단계: 사용자 피드백 이미지
    - 서비스 운영하면서 누적
    - 가장 실제 환경에 가까운 데이터
    - 시간이 지날수록 모델이 강해짐
```

### 크롤링 타겟 사이트

| 사이트 | 특징 | 언어판 |
|--------|------|--------|
| TCGPlayer | 판매자 실사 이미지 다량, 공식 API도 있음 | EN |
| eBay | 전 세계 판매자 촬영, 공식 API 있음 | KO/EN/JP |
| 번개장터 | 한국 실사 이미지 풍부 | KO |
| 당근마켓 | 한국 실사 이미지 풍부 | KO |
| 메루카리 | 일본 실사 이미지 풍부 | JP |
| Cardmarket | 유럽 쪽, EN/JP 다량 | EN/JP |

### 크롤링 시 수집 데이터
이미지 가져올 때 아래 데이터를 **반드시 함께 수집**

| 필드 | 설명 |
|------|------|
| image | 카드 실사 이미지 |
| card_id | 카드 식별자 |
| price | 판매가 or 낙찰가 |
| date | 판매 날짜 |
| source | 출처 사이트 |
| condition | 카드 상태 (있으면 수집) |

### 수집 데이터 활용
- **image + card_id** → 학습 데이터
- **price + date + source** → 시세 히스토리 DB
- 날짜 있으면 시세 변동 그래프, 최근 시세 등 기능 확장 가능
- 재크롤링 없이 시세 기능 바로 붙일 수 있음

### 예상 데이터 규모
| 출처 | 예상 이미지 수 | 품질 |
|------|--------------|------|
| TCG API | ~50,000장 (KO/EN/JP) | 스튜디오 컷 |
| 크롤링 | 수만~수십만장 | 실사 |
| 사용자 피드백 | 운영 후 누적 | 실사 |

---

## 플라이휠 구조

```
[1단계] 초기 학습
    TCG API 이미지 (KO/EN/JP) + 크롤링 실사 이미지
    → DINOv2 파인튜닝
    → 기초 인식 가능

[2단계] 서비스 운영
    사용자가 카드 스캔
    → 인식 결과 제시

[3단계] 피드백 수집
    틀렸을 때 사용자가 정답 카드 선택
    → 해당 이미지 + 정답 라벨 저장

[4단계] 재학습
    누적된 실사 데이터로 주기적 재파인튜닝
    → 인식률 점점 향상
    → 2단계로 돌아감
```

---

## 프로젝트 구조

```
scanner_v2/
├── data/
│   ├── download_cards.py       # TCG API에서 KO/EN/JP 카드 이미지 수집
│   ├── crawlers/
│   │   ├── tcgplayer.py        # TCGPlayer 크롤러
│   │   ├── ebay.py             # eBay 크롤러
│   │   ├── bunjang.py          # 번개장터 크롤러
│   │   ├── daangn.py           # 당근마켓 크롤러
│   │   └── mercari.py          # 메루카리 크롤러
│   ├── augment.py              # 데이터 증강 (홀로그램 시뮬레이션)
│   └── feedback/               # 사용자 피드백 실사 이미지
│       ├── images/
│       └── labels.json
├── train/
│   ├── dataset.py              # 학습 데이터셋 (API + 크롤링 + 피드백 통합)
│   ├── train.py                # DINOv2 파인튜닝 메인
│   └── loss.py                 # NT-Xent Contrastive Loss
├── db/
│   ├── build_db.py             # FAISS DB 구축
│   ├── card_db.faiss           # 벡터 DB
│   └── card_meta.json          # 카드 메타데이터
├── scan/
│   └── scan_card.py            # 카드 인식 메인 (Spring Boot에서 호출)
├── feedback/
│   └── collect_feedback.py     # 피드백 수집 및 저장
└── requirements.txt
```

---

## Step 1. 데이터 수집 (download_cards.py)

### card_meta.json 구조
```json
{
  "sv4-097": {
    "name": "Mismagius ex",
    "number": "097/080",
    "set": "Scarlet & Violet",
    "rarity": "SR",
    "images": {
      "ko": "card_images/ko/sv4-097.png",
      "en": "card_images/en/sv4-097.png",
      "jp": "card_images/jp/sv4-097.png"
    }
  }
}
```

- API 키: https://pokemontcg.io 무료 발급
- 언어판이 하나만 있는 카드는 있는 것만 수집
- 총 용량 약 2~4GB (3개 언어)

---

## Step 2. 데이터 증강 (augment.py)

KO/EN/JP 이미지가 이미 다양성을 제공하므로 증강 강도는 중간 수준으로 충분

| 증강 기법 | 목적 |
|----------|------|
| 밝기/대비 변화 | 조명 차이 시뮬레이션 |
| 랜덤 회전/크롭 | 카메라 각도 차이 |
| 글레어 오버레이 | 홀로그램 반사 시뮬레이션 (핵심) |
| 색조 변화 | 카메라 화이트밸런스 차이 |
| 블러 | 초점 흔들림 |

---

## Step 3. 파인튜닝 (train.py)

### Contrastive Learning 방식
- 같은 card_id의 이미지 (KO/EN/JP + 증강 + 피드백) → 임베딩이 **가깝게**
- 다른 card_id의 이미지 → 임베딩이 **멀게**
- 분류 레이어 없음 → 새 카드 추가 시 DB만 업데이트

### Positive Pair 구성
```
sv4-097 KO ↔ sv4-097 EN       ✅ positive
sv4-097 KO ↔ sv4-097 JP       ✅ positive
sv4-097 KO ↔ sv4-097 실사촬영  ✅ positive
sv4-097 KO ↔ sv4-098 EN       ❌ negative
```

### 학습 설정
```
모델:      facebook/dinov2-base
optimizer: AdamW
lr:        1e-5
batch:     32 (M4 Pro 기준)
epochs:    20~30
device:    mps
loss:      NT-Xent (Contrastive Loss)
```

### 학습 시간 예상 (M4 MacBook Pro MPS)
- 초기 학습: 약 3~5시간
- 피드백 추가 재학습: 30분~2시간

---

## Step 4. FAISS DB 구축 (build_db.py)

```
카드 이미지 로드 (KO/EN/JP 전부)
    → DINOv2 임베딩
    → 정규화 (L2)
    → FAISS IndexFlatIP에 추가
    → card_id로 메타 매핑
```

출력:
- `db/card_db.faiss`
- `db/card_meta.json`

---

## Step 5. 카드 인식 API (scan_card.py)

### Spring Boot 연동 방식
현재 `/api/scanner/identify` 엔드포인트가 Ollama를 호출하는 부분을
Python FastAPI로 교체 (그레이딩 서비스와 동일한 구조, port 8082)

```
POST /api/scanner/identify
    → Spring Boot
    → Python FastAPI (port 8082)
    → DINOv2 임베딩 + FAISS 검색
    → card_id 반환
    → Spring Boot → cards DB 조회
    → Flutter 모달
```

### 인식 결과 예시
```json
{
  "status": "success",
  "data": [
    {
      "cardId": "sv4-097",
      "name": "무우마직 ex",
      "rarityCode": "SR",
      "score": 0.94,
      "candidates": [
        { "cardId": "sv4-097", "name": "무우마직 ex", "score": 0.94 },
        { "cardId": "sv4-096", "name": "무우마", "score": 0.61 }
      ]
    }
  ]
}
```

### 신뢰도 처리
| score | 처리 |
|-------|------|
| > 0.85 | 확정 → 바로 모달 표시 |
| 0.6 ~ 0.85 | 후보 여러 개 제시 → 사용자 선택 |
| < 0.6 | 인식 실패 → 검색 fallback 안내 |

---

## Step 6. 피드백 수집 (collect_feedback.py)

### 플로우
```
인식 결과 제시
    → 사용자 "맞아요" → 끝
    → 사용자 "틀렸어요"
        → 후보 목록 or 검색으로 정답 선택
        → 이미지 + 정답 card_id 저장
        → labels.json 업데이트
```

### labels.json 구조
```json
[
  {
    "image": "feedback/images/20260430_143022.jpg",
    "card_id": "sv4-097",
    "predicted": "sv4-098",
    "timestamp": "2026-04-30T14:30:22"
  }
]
```

### 재학습 트리거
- 피드백 100건마다 재파인튜닝 권장
- 재학습 후 FAISS DB 재구축

---

## 기존 아키텍처와 통합

### 변경 사항
| 항목 | 기존 | 변경 후 |
|------|------|---------|
| 스캐너 엔진 | Ollama llava (port 11434) | DINOv2 FastAPI (port 8082) |
| 인식 방식 | 수록번호 OCR | 이미지 임베딩 유사도 검색 |
| 속도 | 첫 호출 10~20초 | 1~2초 이내 |
| 오프라인 | Ollama 서버 필요 | 로컬 모델로 완전 오프라인 가능 |
| 확장성 | 모델 크기 고정 | DB만 업데이트하면 신규 카드 대응 |

### 유지되는 것
- Spring Boot `/api/scanner/identify` 엔드포인트 (내부 호출 대상만 변경)
- Flutter 스캐너 화면 UX (모달, 자산 등록 플로우)
- cards DB 구조

### 추가되는 것
```
grading/    → Python FastAPI (port 8081) - 기존 유지
scanner_v2/ → Python FastAPI (port 8082) - 신규
```

---

## 개발 환경

| 항목 | 내용 |
|------|------|
| 학습 | M4 MacBook Pro (MPS 가속) |
| 추론 | M2 MacBook Air / M4 MacBook Pro |
| Python | 3.11+ |
| 프레임워크 | FastAPI (그레이딩 서비스와 동일 구조) |

---

## 필요 라이브러리

```
torch
torchvision
transformers       # DINOv2
faiss-cpu
opencv-python
pillow
requests
tqdm
fastapi
uvicorn
```

---

## 개발 순서

```
1. 크롤러 작성 (TCGPlayer, eBay, 번개장터 등)
   → 이미지 + 시세 + 날짜 동시 수집

2. TCG API 이미지 수집 (KO/EN/JP)

3. DINOv2 파인튜닝 (M4 Pro)
   → 초기: API 이미지 + 크롤링 실사 이미지

4. FAISS DB 구축

5. FastAPI 서버 작성 (port 8082)

6. Spring Boot /api/scanner/identify → Ollama 제거, FastAPI 호출로 교체

7. Flutter 피드백 UI 추가 (틀렸어요 버튼 + 정답 선택)

8. 피드백 100건마다 재학습 사이클 운영
```
