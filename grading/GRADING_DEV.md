# 그레이딩 알고리즘 개발 문서

## 현재 상태 (2026-04-28)

### 구조
```
grading/
├── main.py          # FastAPI 서버 (port 8081)
├── analyzer.py      # 핵심 분석 알고리즘 (GradingAnalyzer)
├── models.py        # AnalysisResult 모델
├── tests/           # pytest 테스트
└── venv/            # Python 가상환경
```

### 서버 실행
```bash
cd /Users/nightfury/work_temp/pokemon_card_app/grading
source venv/bin/activate
uvicorn main:app --host 0.0.0.0 --port 8081
```

### API
```
POST /api/grading/analyze
Content-Type: multipart/form-data

files[0] = 앞면 전체
files[1] = 뒷면 전체
files[2-5] = 앞면 코너 (좌상, 우상, 좌하, 우하)
files[6-9] = 뒷면 코너 (좌상, 우상, 좌하, 우하)
```

---

## 알고리즘 v2.1 (2026-04-27 수정) — 현재 버전

### 배점
| 항목 | 가중치 | 비고 |
|------|--------|------|
| 센터링 | 15% | 앞면 사용 |
| 코너 | 35% | 8개 코너 평균 |
| 표면 | 25% | 앞면+뒷면 평균 |
| 백화 | 25% | 뒷면 + 뒷면 코너 4개 |

heavy_whitening=True이면 총점 × 0.85 페널티

### _find_card_in_image(gray)
- **목적**: 사진 속 카드 영역 추출 (배경 분리)
- **방법**: Otsu 이진화 → morphologyEx(CLOSE) → 최대 컨투어 boundingRect
- **검정 배경 대응**: Otsu 실패 시 반전 이미지(`bitwise_not`)로 재시도
- **조건**: 카드 면적 < 전체 이미지 30% 이면 전체 이미지 반환 (fallback)
- **패딩**: 5px 여유

### analyze_centering(front)
- **방법**: 카드 ROI 내 Sobel 그라디언트의 **위치** 기반 마진 측정
  - 외곽 8% 영역에서 argmax → 물리적 카드 엣지 위치 추정
- **점수식**: `max(5.0, 10.0 - (dev / 0.05) * 0.8)` (dev=비율편차)
  - 감도 완화: 1.5 → 0.8 (PSA 최악 센터링도 1~2등급 감점 수준)
  - 최솟값 5.0: 오감지로 인한 폭락 방지
- **총점 기여**: 오감지 빈번하여 `quality_lowest` 계산에서 제외, 별도 완화 캡만 적용
- **알려진 한계**: 아트워크 내부 그라디언트를 카드 엣지로 오인식 → 개선 여지 있음

### analyze_corner(corner_image)
- **방법**: 이미지 중앙 50% 영역에서 Canny 엣지 밀도 측정
- **점수식**: `min(10.0, max(1.0, edge_density * 250))`
- **성능**: 선명한 코너 → 10.0점 (near-mint 카드 정상 동작)

### analyze_surface(image)
- **방법**: 카드 ROI 외곽 **5% 테두리 영역**의 Laplacian 표준편차
  - 아트워크 영역 제외 → 단색 테두리만 분석
  - 스크래치/오염 → Laplacian std 상승 → 점수 하락
- **점수식**: `max(4.0, min(10.0, 10.0 - max(0, lap_std - 5.0) * 0.30))`
- **기준값**: 깨끗한 카드 std≈5~8 → 9.1~10점
- **최솟값 4.0**: 조명/배경 조건 변동에 의한 과도한 감점 방지 (이전 1.0 → 수정)

### analyze_whitening(image)
- **방법**: 카드 ROI 외곽 **4% 테두리 영역** HSV 분석
  - 실제 백화 조건: **S ≤ 10, V ≥ 210** (잉크 벗겨진 흰 종이)
  - 포켓볼 흰색 디자인(S≈15, V≈205) → 제외됨
  - heavy=True 조건: ratio > 0.05
- **점수식**: `max(1.0, 10.0 - ratio * 100)`
- **기준값**: 깨끗한 카드 뒷면 ratio≈0.0065 → 9.4점

---

## v2 → v2.1 변경 이유 (버그 기록)

| 항목 | v2 방식 | 문제 | v2.1 방식 |
|------|---------|------|---------|
| 카드 검출 | Otsu 이진화만 사용 | 검정 배경에서 카드 미검출 → fallback 전체 이미지 → 배경 노이즈 | Otsu 실패 시 `bitwise_not` 반전 이미지로 재시도 |
| 표면 최솟값 | `max(1.0, ...)` | 배경 노이즈로 1.0 급락 | `max(4.0, ...)` |
| 센터링 감도 | `(dev/0.05)*1.5` | 오감지 시 1.2까지 폭락 → 총점 3점대 | `(dev/0.05)*0.8`, 최솟값 `5.0` |
| 총점 캡 | `lowest=min(모든항목)` | 센터링 오감지가 총점 폭락 유발 | `quality_lowest=min(코너,표면,화이트닝)` 센터링 제외 |
| 총점 반환 | 단일 점수 | 사진 조건 따라 ±1 오차 → 사용자 기대 불일치 | 단일값 + ±1.0 범위 표시 (Flutter 클라이언트) |
| 결과 UI | 점수만 표시 | 왜 그 점수인지 알 수 없음 | 항목별 사유 텍스트 표시 (centeringDetail 등) |

**v2.1 이후 권장 촬영 조건**: 흰 종이 단색 배경, 플래시 OFF, 카드가 화면 70% 이상 차지

---

## v1 → v2 변경 이유 (버그 기록)

| 항목 | v1 방식 | 문제 | v2 방식 |
|------|---------|------|---------|
| 표면 | HoughLinesP 스크래치 카운트 | 아트워크 선도 카운트 → 항상 1.0 | Laplacian std (테두리만) |
| 센터링 | Canny 컨투어 내외곽 | 아트워크를 내부 rect로 오인 → 2.1 | Sobel 그라디언트 위치 |
| 백화 | S≤20, V≥185, margin=8% | 포켓볼 디자인 오감지 → 3.2 | S≤10, V≥210, margin=4% |
| 공통 | 전체 이미지 그대로 분석 | 사진 배경이 카드로 오인식 | _find_card_in_image로 먼저 분리 |

---

## 앞으로 해야 할 것

### 완료 (v2.1)
- [x] 검정 배경 카드 검출 개선 (bitwise_not 재시도)
- [x] 표면 최솟값 4.0, 센터링 최솟값 5.0
- [x] 센터링 감도 완화 (1.5 → 0.8)
- [x] 총점 캡 로직 (quality_lowest 센터링 제외)
- [x] 항목별 사유 텍스트 (detail 필드)
- [x] 결과 화면 ±1.0 범위 표시
- [x] grading_screen 촬영 주의사항 / 사진 선택 순서 안내

### 우선순위 높음
- [ ] **센터링 알고리즘 개선**: Sobel argmax 오감지 빈번
  - 방향: 카드 테두리 색(노랑/파랑) 기반 색상 분리 + 전환점 탐지
- [ ] **갤러리 선택 후 미리보기**: grading_capture_screen에서 선택한 사진 섬네일 확인
  - 앞면/뒷면 혼동 방지 목적

### 우선순위 중간
- [ ] **표면 아트워크 결함 감지**: 현재 테두리 5%만 분석 → 구김/눌림 미감지
- [ ] **홀로그래픽 카드 대응**: SAR/SSR 반사 → 표면 스크래치 오인 가능

### 우선순위 낮음
- [ ] **ML 모델 도입**: 장기적으로 OpenCV → ML 기반 전환

---

## 테스트 방법

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/grading
source venv/bin/activate

# 단위 테스트
pytest tests/

# 실제 이미지로 수동 테스트 (HEIF → JPEG 변환 후)
sips -s format jpeg /path/to/IMG_XXXX.heic --out /tmp/test.jpg
python3 -c "
import cv2, sys
sys.path.insert(0,'.')
from analyzer import GradingAnalyzer
front = cv2.imread('/tmp/front.jpg')
back = cv2.imread('/tmp/back.jpg')
corners = [cv2.imread(f'/tmp/corner{i}.jpg') for i in range(8)]
print(GradingAnalyzer().analyze(front, back, corners))
"
```

---

## 이미지 선택 순서 (앱 기준)
```
step 0: 앞면 전체 → front
step 1: 뒷면 전체 → back
step 2: 앞 좌상단 → corners[0]
step 3: 앞 우상단 → corners[1]
step 4: 앞 좌하단 → corners[2]
step 5: 앞 우하단 → corners[3]
step 6: 뒤 좌상단 → corners[4]  ← whitening 분석에 사용
step 7: 뒤 우상단 → corners[5]  ← whitening 분석에 사용
step 8: 뒤 좌하단 → corners[6]  ← whitening 분석에 사용
step 9: 뒤 우하단 → corners[7]  ← whitening 분석에 사용
```

## PSA 등급 대응표 (참고)
| PSA | 우리 점수 | 특징 |
|-----|---------|------|
| 10 | 9.5+ | 퍼팩트 |
| 9 | 8.0~9.4 | Near Mint |
| 8 | 6.5~7.9 | 경미한 결함 |
| 7 | 5.0~6.4 | 눈에 띄는 결함 |
| 6↓ | 5.0 미만 | 심각한 손상 |
