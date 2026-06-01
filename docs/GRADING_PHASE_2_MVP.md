# Phase 2 — AI 그레이딩 MVP Spec

> 작성: 2026-05-31. 사용자 명시 새 plan 정리. 내일 개발 시작용.

---

## 0. 핵심 변경 (현재 v2.1 → 새 plan)

| 항목 | 현재 v2.1 | 새 plan |
|------|----------|---------|
| 입력 방식 | 갤러리 10장 (앞/뒤/8 코너) | 앱 내 카메라 2장 (앞/뒤) + frame overlay |
| 외곽선 가이드 | 없음 (사용자 임의 촬영) | 우리만의 센터링 frame |
| 코너 분석 | 8 코너 별도 입력 | 자동 ROI 추출 |
| 결함 검출 | Laplacian std (테두리 5%) | 채도/명암 변환 → 결함 visibility |
| 결과 | 점수 + 텍스트 detail | 점수 + 감점 사유 + bbox overlay |
| 등급 | PSA 매핑 (9.5+→PSA10) | 자체 S+/S/S-/A+/A/A-/B+/B/C (PSA 매핑 0) |
| 점수 단위 | 0.5 | **0.1** (납득 가능) |

**시장 mechanism = weakest link rule** — 한 항목이 심하면 전체 등급도 같이 떨어짐.

---

## 1. Frame Overlay — 우리만의 센터링 틀

- Legends 그리드 카드 따라하기 X
- **우리 알고리즘 측정 reference + 정렬 가이드** 가 들어간 자체 frame
- 카드 외곽 (검정 테두리) 일치 가이드 + 4 코너 marker + 중앙 십자선

```
┌─────────────────────────┐
│ ┌───────────────────┐ │  ← 카드 외곽 정렬
│ │    ┌───┼───┐     │ │  ← 우리만의 센터링 reference
│ │    │       │     │ │
│ │    │   ✚   │     │ │  ← 중앙 십자선
│ │    │       │     │ │
│ │    └───┼───┘     │ │
│ └───────────────────┘ │
│  ▢            ▢      │  ← 4 코너 marker
└─────────────────────────┘
```

활용:
- 알고리즘이 frame reference 로 카드 외곽 자동 detect → 센터링 측정 정확도 ↑ (현재 Sobel argmax 오감지 해결)
- 4 코너 marker = 코너 분석 영역 자동 추출

---

## 2. 채도/명암 변환 기반 결함 visibility

홀로/패턴 카드 = 정상 상태 균일 → 채도/명암 변환 시 결함 (찍힘/화이트닝) 두드러짐.

### 결함 검출 함수 spec

```python
def detect_whitening_regions(card_roi):
    """HSV S 부스트 → 흰 영역 highlight → bbox list"""
    hsv = cv2.cvtColor(card_roi, cv2.COLOR_BGR2HSV)
    hsv[:,:,1] = np.clip(hsv[:,:,1] * 2.0, 0, 255)
    boosted = cv2.cvtColor(hsv, cv2.COLOR_HSV2BGR)
    diff = cv2.absdiff(boosted, card_roi)
    mask = (diff.sum(axis=2) > THRESHOLD).astype(np.uint8) * 255
    contours = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)[0]
    return [bbox_with_confidence(c) for c in contours if area(c) > MIN_AREA]


def detect_scratch_regions(card_roi):
    """CLAHE local contrast → 미세 스크래치/구김 visible"""
    lab = cv2.cvtColor(card_roi, cv2.COLOR_BGR2LAB)
    l = lab[:,:,0]
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8,8))
    enhanced = clahe.apply(l)
    diff = cv2.absdiff(enhanced, l)
    mask = (diff > THRESHOLD).astype(np.uint8) * 255
    # 선형 패턴 (스크래치) + 점 패턴 (구김) detect
    return detect_linear_and_dot_patterns(mask)


def detect_corner_damage(card_roi):
    """frame 의 4 코너 영역 자동 추출 + 코너별 손상 detect"""
    corners = extract_corner_rois(card_roi)  # frame reference 기준
    return [analyze_corner(c) for c in corners]
```

---

## 3. 등급 산식 — 3중 cap (weakest link rule)

```python
def calculate_grade(weighted_raw: float, metrics: dict, has_major: bool) -> str:
    """
    weighted_raw: 가중평균 float (full precision)
    metrics: {centering, corner, surface, whitening, edge}
    has_major: 심각 결함 여부
    
    핵심: weighted AND min(metrics) 둘 다 충족해야 등급 부여
    """
    min_metric = min(metrics.values())
    
    if weighted_raw >= 9.5 and min_metric >= 9.0 and not has_major:
        return "S+"
    elif weighted_raw >= 9.0 and min_metric >= 8.5 and not has_major:
        return "S"
    elif weighted_raw >= 8.5 and min_metric >= 8.0:
        return "S-"
    elif weighted_raw >= 8.0 and min_metric >= 7.0:
        return "A+"
    elif weighted_raw >= 7.0 and min_metric >= 6.0:
        return "A"
    elif weighted_raw >= 6.0 and min_metric >= 5.0:
        return "A-"
    elif weighted_raw >= 5.0 and min_metric >= 4.0:
        return "B+"
    elif weighted_raw >= 4.0 and min_metric >= 3.0:
        return "B"
    else:
        return "C"


def has_major_defect(metrics: dict, reasons: list) -> bool:
    return (
        any(m < 4.0 for m in metrics.values()) or
        any(r.severity == "major" for r in reasons if r.type == "whitening") and len([r for r in reasons if r.type == "whitening"]) > 1 or
        len([r for r in reasons if r.severity == "major"]) > 1
    )
```

### 케이스 검증

| Metrics | weighted | min | major | 등급 |
|---------|----------|-----|-------|------|
| 9 / 9 / 9 / 1 / 9 | 7.0 | 1 | TRUE | **C** |
| 10 / 10 / 10 / 8 / 10 | 9.55 | 8 | FALSE | **S-** |
| 9.7 / 9.5 / 9.6 / 9.4 / 9.5 | 9.55 | 9.4 | FALSE | **S+** |

### 9단계 등급표

| 등급 | weighted_raw | min_metric | 색상 |
|------|--------------|------------|------|
| S+ | ≥ 9.5 | ≥ 9.0 | 골드 (#FFD700) |
| S  | ≥ 9.0 | ≥ 8.5 | 보라 (#9B59B6) |
| S- | ≥ 8.5 | ≥ 8.0 | 보라 (#BB8FCE) |
| A+ | ≥ 8.0 | ≥ 7.0 | 파랑 (#3498DB) |
| A  | ≥ 7.0 | ≥ 6.0 | 파랑 (#5DADE2) |
| A- | ≥ 6.0 | ≥ 5.0 | 하늘 (#85C1E2) |
| B+ | ≥ 5.0 | ≥ 4.0 | 초록 (#27AE60) |
| B  | ≥ 4.0 | ≥ 3.0 | 올리브 (#7DCEA0) |
| C  | 그 외 | - | 회색 (#95A5A6) |

---

## 4. Models (Pydantic)

```python
from typing import Optional, List, Tuple
from pydantic import BaseModel


class DeductionReason(BaseModel):
    """감점 사유 — 결과 화면 핵심 (계층적: 요약 카드 + 탭 상세)"""
    id: str             # uuid 또는 idx (Flutter 탭/navigation 용)
    type: str           # centering / corner / surface / whitening / edge
    label: str          # 카드 표시: "뒷면 좌상단 코너 백화"
    side: str           # front / back
    position: str       # top_left / top_right / bottom_left / bottom_right / center / center_left ...
    severity: str       # minor / moderate / major
    confidence: float   # 0.0 ~ 1.0
    penalty: float      # 감점값
    bbox: Optional[Tuple[float, float, float, float]]  # normalized (x, y, w, h)
    explanation: str    # 상세 화면 분석 근거 텍스트


class DefectRegion(BaseModel):
    """이미지 overlay 용 — 시각화 전용"""
    type: str           # whitening / scratch / dent / corner_damage
    bbox: Tuple[float, float, float, float]  # normalized
    side: str           # front / back
    color: str          # HEX


class AnalysisResult(BaseModel):
    # 항목별 점수 (display = round 0.1, internal raw)
    centering_score: float
    corner_score: float
    surface_score: float
    whitening_score: float
    edge_score: float
    
    # 종합
    weighted_score: float       # raw float
    total_score_display: float  # round(weighted_score, 1)
    
    # 등급 (자체 9단계, PSA 매핑 0)
    grade: str         # S+/S/S-/A+/A/A-/B+/B/C
    grade_color: str   # HEX
    
    # 감점 + 결함
    deduction_reasons: List[DeductionReason]
    defect_regions: List[DefectRegion]
    
    # 부수
    has_major_defect: bool
    heavy_whitening: bool
    detection_confidence: float
```

---

## 5. 결과 화면 — 계층적 (메인 요약 + 탭 상세)

### L0 메인 결과 화면 — 요약만 (인지 부하 ↓)

```
1. 큰 등급 표시 (S+/S/...) + 총점 (0.1 단위)
2. 한 줄 요약 ("백화 항목이 가장 낮게 측정되었습니다")
3. 항목별 점수 + 최저 칩 (centering/corner/surface/whitening/edge)
4. 감점 사유 카드 리스트 (탭 가능 카드 3-5개)
   - label / -penalty / 신뢰도% / → 화살표
5. PokeFolio 자체 평가 disclaimer
```

### L1 감점 사유 상세 화면 — 탭한 사용자만

`grading_deduction_detail_screen.dart` (신규 또는 BottomSheet)

```
1. AppBar: 감점 사유 label
2. 원본 사진 + bbox/mask overlay
   - [원본] / [강조] 토글 (채도 강조된 이미지 vs 원본)
3. 감점 점수 + 신뢰도 + 위치 + 심각도
4. 분석 근거 텍스트 (DeductionReason.explanation)
5. 이전/다음 사유 navigation (allReasons 안 swipe)
```

### Wireframe

```
┌────────────────────────────────────┐
│ [원본 사진 + 결함 overlay]        │
│  ┌──────────────────┐              │
│  │   ▌ 백화        │  ← bbox      │
│  │      ▬▬ 스크래치│              │
│  └──────────────────┘              │
│                                    │
│       ╔═══════╗                    │
│       ║   A   ║  ← 큰 grade        │
│       ║ 7.9   ║                    │
│       ╚═══════╝                    │
│                                    │
│ ▼ 항목별 점수 (0.1 단위)          │
│   센터링 8.7 / 10                 │
│   코너   9.1 / 10                 │
│   표면   7.8 / 10                 │
│   백화   6.4 / 10  ← 최저          │
│   엣지   8.5 / 10                 │
│                                    │
│ ▼ 감점 사유 (3가지)               │
│ 1. 뒷면 좌상단 코너 백화          │
│    ⓘ -1.2 점 / back top-left      │
│    신뢰도 86%                      │
│                                    │
│ 2. 앞면 중앙우측 표면 스크래치    │
│    ⓘ -0.6 점 / front middle-right │
│    신뢰도 74%                      │
│                                    │
│ 3. 센터링 좌우 편차               │
│    ⓘ -0.4 점 / 좌우 비율 46:54    │
│                                    │
│ ─────────────────────              │
│ PokeFolio AI 자체 평가             │
│ ⓘ 외부 등급사(PSA/BRG) 공식 등급 │
│   과는 별개의 자체 평가입니다      │
└────────────────────────────────────┘
```

---

## 6. 2일 MVP 작업 plan

### Day 1 — Backend (`grading/`)

1. `analyzer.py` 확장
   - `detect_whitening_regions()` — HSV S 부스트
   - `detect_scratch_regions()` — CLAHE local contrast
   - `detect_corner_damage()` — frame reference 4 코너 자동 추출
   - `analyze_centering_with_reasons()` — frame reference 사용
   - 각 metric 함수 → `(score, reasons)` 동시 반환
   - `calculate_grade()` — 9단계 cap
   - `has_major_defect()` — 자동 trigger

2. `models.py` 확장
   - `DeductionReason`, `DefectRegion` 신규
   - `AnalysisResult` 확장 (grade, grade_color, defect_regions, deduction_reasons)

3. `main.py` 그대로 (앞/뒤 2장 입력 유지)

4. `pytest` 신규 case
   - 케이스 1 (9/9/9/1 → C)
   - 케이스 2 (10/10/10/8 → S-)
   - 케이스 3 (9.7/9.5/9.6/9.4/9.5 → S+)

### Day 2 — Flutter (`front/lib/features/grading/`)

1. `grading_capture_screen.dart` 재작성
   - camera plugin (camera_avfoundation 또는 image_picker)
   - `CustomPainter` 로 우리만의 frame overlay
   - 앞/뒷 2-step
   - 자동 capture (외곽 일치) 또는 수동 shutter

2. `grading_result_screen.dart` 확장
   - Stack + 결함 bbox overlay (`CustomPainter` 또는 `Positioned`)
   - 큰 grade 표시 + 색상
   - 점수 0.1 단위 표시
   - 감점 사유 ListView
   - PSA 매핑 0, 자체 평가 disclaimer

3. 통합 테스트 + IPA 빌드

---

## 7. 정책 — 절대 금지

- ML 모델 도입 (출시 후 Phase 1 dataset 수집 후)
- 데이터셋 구축 작업 (출시 후)
- PSA / BRG / CGC / BGS 매핑 (자체 등급 만)
- 작업 범위 4-5일짜리로 확장 (2일 MVP 유지)
- 도감 / 시세 / 거래 코드 건드림
- 자동 촬영 완성도 집착 (MVP = 수동 셔터)
- 레어도별 홀로 패턴 분리 (출시 후)
- 모든 결함 정확 판정 (false positive 인정)
- "스크래치 확정" 단정 표현 (반드시 "후보")

## 7.5 기술 세부 사양

### 촬영 (Flutter)
- 패키지: `camera` (공식 Flutter 플러그인, CameraPreview + 사진 + 스트림)
- **수동 셔터 + 정렬 가이드** (자동촬영 X — 외곽선 인식 실패/조명 반사/홀로 반짝임/손-배경 오인식 risk)
- CustomPainter overlay: 카드 외곽 + 중앙 십자 + 4 코너 marker
- 앞면 → 뒷면 2-step

### ROI 추출 (백엔드)
```
1. 이미지 resize
2. edge detect (Canny)
3. contour 추출
4. 사각형 후보 중 카드 비율 (~2.5:3.5) 선택
5. perspective transform (카드 정면 보정) ← 필수
6. front_roi / back_roi 정규화 후 분석
```

촬영 frame overlay 가 있으면 ROI 추출 난이도 ↓ (사용자가 이미 정렬).

### 백화 검출 — HSV S+V 조합
```python
hsv = cv2.cvtColor(roi, cv2.COLOR_BGR2HSV)
mask = (hsv[:,:,1] < S_LOW) & (hsv[:,:,2] > V_HIGH)  # S 낮음 + V 높음
mask &= edge_corner_mask  # 코너/엣지 영역 우선
mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel)  # 노이즈 제거
contours → bbox + confidence
```

뒷면 코너/엣지 영역에서 효과 ↑.

### 스크래치/찍힘 검출 — LAB L + CLAHE
```python
lab = cv2.cvtColor(roi, cv2.COLOR_BGR2LAB)
l = lab[:,:,0]  # L 채널
clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8,8))
enhanced = clahe.apply(l)
diff = cv2.absdiff(enhanced, l)
mask = diff > THRESHOLD

# 선형 패턴 (스크래치) 분리
linear_contours = filter(lambda c: aspect_ratio(c) > 4, contours)
# 점형 패턴 (찍힘) 분리
dot_contours = filter(lambda c: 1 < aspect_ratio(c) < 4 and area(c) < 100, contours)
```

홀로 카드 반사 = false positive 가능 → label "스크래치 후보" / "표면 이상 후보".

### 센터링 검출 — frame reference + 카드 내부 border
```
1. 카드 ROI 추출
2. 카드 내부 검정 border 영역 탐색
3. 좌/우/상/하 margin 측정
4. 비율 (예: 46:54)
5. 편차에 따라 점수화
```

reasons.explanation: "좌우 비율 46:54"

### 결함 라벨 — "후보" 정책 (false positive 안전)
- ✅ "백화 후보"
- ✅ "스크래치 후보"
- ✅ "표면 이상 후보"
- ❌ "스크래치 확정"
- ❌ "백화 있음"

이유: 초기 버전 false positive (홀로 반사 / 조명 / 슬리브 먼지 / 배경 그림자 / 카드 패턴) 가능성 ↑. 단정 표현 = 사용자 신뢰 손상.

## 7.6 2일 MVP 범위 (사용자 명시)

### 가능 (2일 안)
- 카메라 frame overlay
- 앞/뒤 2장 입력
- ROI 추출 + perspective transform
- HSV 백화 + CLAHE 스크래치 검출
- 0.1 단위 점수
- S/A/B/C 9단계 + 3중 cap
- DeductionReason 구조화 (id, bbox, explanation 포함)
- L0 메인 + L1 상세 (사진 + bbox)
- 결함 라벨 "후보" 정책

### 금지 (2일 안 X)
- 자동 촬영 완성도 집착
- 진짜 ML 학습
- 레어도별 홀로 패턴 분리
- 모든 결함 정확 판정
- 외부 등급사 환산

---

## 8. 정책 — Tier 1 (commit 316ff049) 유지 + 강화

- AI 예측 명시
- 외부 등급사 아님 disclaimer 상시
- `certNumber` APP- prefix
- 친화적 실패 UX
- **PSA / BRG 명칭 = disclaimer 만** (등급 매핑 X)

---

## 9. 미세 caveat — display ↔ grade boundary

```
raw 8.49 → display 8.5 + grade A+ (8.49 < 8.5)
raw 8.50 → display 8.5 + grade S-

→ display 둘 다 8.5 인데 grade 다를 수 있음 (사용자 혼란 가능)

해결:
A. raw boundary (사용자 명시 그대로) — 정확하지만 가끔 혼란
B. round boundary 일치 — display ↔ grade 일치, 사용자 직관

→ 권장 = B (구현 시 결정)
```

---

## 10. 출시 후 (Phase 2 이후)

- Phase 1 dataset 수집 (PSA/BRG 실제 등급 라벨 + 사용자 신고)
- 목표 dataset: PSA/BRG 라벨 300장 + 신고 200건
- Phase 2 Heuristic 개선 (센터링 색상 기반, 표면 아트영역, 홀로 mask)
- Phase 3 ML 도입 (Defect Detector / Centering Regressor / Holo Segmenter / Score Calibrator)
