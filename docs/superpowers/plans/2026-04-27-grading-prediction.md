# 카드 등급 예측 기능 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 포켓몬 카드 사진 10장을 입력받아 센터링/코너/표면/화이트닝 항목별 점수와 종합 예상 등급(소수점 1자리)을 반환하는 기능 구현. 하단 탭 채팅 → 등급으로 교체.

**Architecture:** Flutter(사진 촬영 UI) → Spring Boot(프록시 + 결과 저장) → Python FastAPI(OpenCV 분석 엔진). FastAPI는 포트 8081에 별도 서비스로 실행. 외부 Vision API 미사용.

**Tech Stack:** Python 3.10+, FastAPI, OpenCV (opencv-python-headless), Pydantic, pytest / Spring Boot (Java 17), Lombok, Spring Web / Flutter, camera 패키지(기존), go_router

---

## 파일 구조

### 신규 생성
```
grading/
├── main.py                        FastAPI 앱 진입점
├── analyzer.py                    OpenCV 분석 엔진 (센터링/코너/표면/화이트닝)
├── models.py                      Pydantic 요청/응답 모델
├── requirements.txt
└── tests/
    └── test_analyzer.py           pytest 단위 테스트

back/src/main/java/com/fury/back/domain/grading/
├── GradingResult.java             JPA 엔티티
├── GradingResultRepository.java
├── GradingService.java            인터페이스
├── GradingServiceImpl.java        FastAPI 프록시 + DB 저장
├── GradingController.java
└── dto/
    ├── GradingAnalysisDto.java    FastAPI 응답 매핑용
    └── GradingResultDto.java      클라이언트 응답용

front/lib/features/grading/
├── grading_screen.dart            등급 탭 메인 (안내 + 시작하기)
├── grading_capture_screen.dart    10장 단계별 촬영
└── grading_result_screen.dart     항목별 + 종합 점수 결과

db/grading_results.sql             DDL
```

### 수정
```
front/lib/features/shell/main_shell.dart          채팅 탭 → 등급 탭
front/lib/core/router/app_router.dart             /grading 라우트 추가
front/lib/core/constants/api_constants.dart       grading API 경로 추가
back/src/main/resources/application.properties   grading.service.url 추가
```

---

## Task 1: Python FastAPI 프로젝트 셋업

**Files:**
- Create: `grading/requirements.txt`
- Create: `grading/models.py`
- Create: `grading/main.py`

- [ ] **Step 1: requirements.txt 생성**

```
fastapi==0.111.0
uvicorn==0.29.0
python-multipart==0.0.9
opencv-python-headless==4.9.0.80
numpy==1.26.4
pytest==8.2.0
httpx==0.27.0
```

- [ ] **Step 2: 가상환경 생성 및 패키지 설치**

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/grading
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Expected: Successfully installed fastapi ... opencv-python-headless ...

- [ ] **Step 3: models.py 생성**

```python
from pydantic import BaseModel

class AnalysisResult(BaseModel):
    centering_score: float
    corner_score: float
    surface_score: float
    whitening_score: float
    total_score: float
    heavy_whitening: bool
```

- [ ] **Step 4: main.py 생성**

```python
from fastapi import FastAPI, File, UploadFile
from models import AnalysisResult
from analyzer import GradingAnalyzer
import numpy as np
import cv2

app = FastAPI()
analyzer = GradingAnalyzer()

@app.post("/analyze", response_model=AnalysisResult)
async def analyze(
    front: UploadFile = File(...),
    back: UploadFile = File(...),
    corner_front_tl: UploadFile = File(...),
    corner_front_tr: UploadFile = File(...),
    corner_front_bl: UploadFile = File(...),
    corner_front_br: UploadFile = File(...),
    corner_back_tl: UploadFile = File(...),
    corner_back_tr: UploadFile = File(...),
    corner_back_bl: UploadFile = File(...),
    corner_back_br: UploadFile = File(...),
):
    async def read_image(upload: UploadFile):
        data = await upload.read()
        arr = np.frombuffer(data, np.uint8)
        return cv2.imdecode(arr, cv2.IMREAD_COLOR)

    front_img = await read_image(front)
    back_img = await read_image(back)
    corners = [
        await read_image(corner_front_tl),
        await read_image(corner_front_tr),
        await read_image(corner_front_bl),
        await read_image(corner_front_br),
        await read_image(corner_back_tl),
        await read_image(corner_back_tr),
        await read_image(corner_back_bl),
        await read_image(corner_back_br),
    ]

    return analyzer.analyze(front_img, back_img, corners)

@app.get("/health")
def health():
    return {"status": "ok"}
```

- [ ] **Step 5: analyzer.py 스텁 생성 (테스트 작성 전 인터페이스만)**

```python
import cv2
import numpy as np
from models import AnalysisResult

class GradingAnalyzer:
    def analyze(self, front, back, corners: list) -> AnalysisResult:
        raise NotImplementedError
```

- [ ] **Step 6: 서버 기동 확인**

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/grading
source venv/bin/activate
uvicorn main:app --port 8081 --reload
```

브라우저에서 `http://localhost:8081/health` → `{"status": "ok"}` 확인

- [ ] **Step 7: 커밋**

```bash
git add grading/
git commit -m "feat: Python FastAPI grading service 초기 셋업"
```

---

## Task 2: 센터링 분석 구현 (TDD)

**Files:**
- Create: `grading/tests/test_analyzer.py`
- Modify: `grading/analyzer.py`

- [ ] **Step 1: 테스트용 합성 이미지 헬퍼 작성**

`grading/tests/test_analyzer.py`:

```python
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import cv2
import numpy as np
import pytest
from analyzer import GradingAnalyzer

def make_card_image(width=400, height=560, lr_offset=0, tb_offset=0):
    """카드 이미지 합성. lr_offset>0이면 좌측 여백이 더 큼 (오른쪽 치우침)."""
    img = np.ones((height, width, 3), dtype=np.uint8) * 200  # 연한 회색 배경 (테두리)
    # 내부 인쇄 영역: 기본 10% 여백, offset 적용
    margin = int(min(width, height) * 0.08)
    left = margin + lr_offset
    right = width - margin + lr_offset
    top = margin + tb_offset
    bottom = height - margin + tb_offset
    left = max(5, min(left, width - 5))
    right = max(left + 10, min(right, width - 5))
    top = max(5, min(top, height - 5))
    bottom = max(top + 10, min(bottom, height - 5))
    cv2.rectangle(img, (left, top), (right, bottom), (50, 50, 150), -1)  # 인쇄 영역
    cv2.rectangle(img, (2, 2), (width - 2, height - 2), (30, 30, 30), 3)  # 카드 외곽
    return img

analyzer = GradingAnalyzer()

def test_centering_perfect():
    img = make_card_image(lr_offset=0, tb_offset=0)
    score = analyzer.analyze_centering(img)
    assert score >= 9.0, f"완벽한 센터링인데 점수가 낮음: {score}"

def test_centering_off():
    img = make_card_image(lr_offset=30, tb_offset=0)
    score = analyzer.analyze_centering(img)
    assert score < 9.0, f"치우친 센터링인데 점수가 높음: {score}"

def test_centering_returns_float():
    img = make_card_image()
    score = analyzer.analyze_centering(img)
    assert isinstance(score, float)
    assert 1.0 <= score <= 10.0
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/grading
source venv/bin/activate
python -m pytest tests/test_analyzer.py::test_centering_perfect -v
```

Expected: FAIL with `NotImplementedError`

- [ ] **Step 3: 센터링 분석 구현**

`grading/analyzer.py` 전체:

```python
import cv2
import numpy as np
from models import AnalysisResult  # uvicorn을 grading/ 디렉토리에서 실행하므로 절대 import 사용

class GradingAnalyzer:

    def analyze_centering(self, image) -> float:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 30, 100)
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return 5.0
        card_contour = max(contours, key=cv2.contourArea)
        cx, cy, cw, ch = cv2.boundingRect(card_contour)
        roi = image[cy:cy+ch, cx:cx+cw]
        gray_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
        inner_edges = cv2.Canny(gray_roi, 20, 80)
        inner_contours, _ = cv2.findContours(inner_edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if len(inner_contours) < 2:
            return 8.0
        inner_contours = sorted(inner_contours, key=cv2.contourArea, reverse=True)
        ix, iy, iw, ih = cv2.boundingRect(inner_contours[1])
        left_m = ix
        right_m = cw - (ix + iw)
        top_m = iy
        bottom_m = ch - (iy + ih)
        lr_total = left_m + right_m
        tb_total = top_m + bottom_m
        lr_ratio = left_m / lr_total if lr_total > 0 else 0.5
        tb_ratio = top_m / tb_total if tb_total > 0 else 0.5
        lr_dev = abs(lr_ratio - 0.5)
        tb_dev = abs(tb_ratio - 0.5)
        lr_score = max(1.0, 10.0 - (lr_dev / 0.05) * 1.5)
        tb_score = max(1.0, 10.0 - (tb_dev / 0.05) * 1.5)
        return round(min(10.0, (lr_score + tb_score) / 2), 1)

    def analyze_corner(self, image) -> float:
        raise NotImplementedError

    def analyze_surface(self, image) -> float:
        raise NotImplementedError

    def analyze_whitening(self, image):
        raise NotImplementedError

    def analyze(self, front, back, corners: list) -> AnalysisResult:
        raise NotImplementedError
```

- [ ] **Step 4: 센터링 테스트 통과 확인**

```bash
python -m pytest tests/test_analyzer.py -k "centering" -v
```

Expected: 3 passed

- [ ] **Step 5: 커밋**

```bash
git add grading/analyzer.py grading/tests/test_analyzer.py
git commit -m "feat: OpenCV 센터링 분석 구현"
```

---

## Task 3: 코너 분석 구현 (TDD)

**Files:**
- Modify: `grading/tests/test_analyzer.py`
- Modify: `grading/analyzer.py`

- [ ] **Step 1: 코너 테스트 추가**

`test_analyzer.py` 하단에 추가:

```python
def make_corner_image(sharp=True):
    """코너 이미지 합성. sharp=True면 선명한 코너, False면 둥글게 마모."""
    img = np.ones((150, 150, 3), dtype=np.uint8) * 180
    if sharp:
        # 선명한 직각 코너
        cv2.rectangle(img, (10, 10), (140, 140), (30, 30, 30), 2)
        cv2.line(img, (10, 10), (30, 10), (0, 0, 0), 3)
        cv2.line(img, (10, 10), (10, 30), (0, 0, 0), 3)
    else:
        # 마모된 코너 — 둥근 사각형
        cv2.ellipse(img, (30, 30), (20, 20), 0, 180, 270, (30, 30, 30), 2)
    return img

def test_corner_sharp():
    img = make_corner_image(sharp=True)
    score = analyzer.analyze_corner(img)
    assert score >= 7.0, f"선명한 코너인데 점수 낮음: {score}"

def test_corner_worn():
    img = make_corner_image(sharp=False)
    score = analyzer.analyze_corner(img)
    assert score <= 8.0, f"마모된 코너인데 점수 높음: {score}"

def test_corner_returns_float():
    img = make_corner_image()
    score = analyzer.analyze_corner(img)
    assert isinstance(score, float)
    assert 1.0 <= score <= 10.0
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
python -m pytest tests/test_analyzer.py -k "corner" -v
```

Expected: FAIL with `NotImplementedError`

- [ ] **Step 3: 코너 분석 구현**

`analyzer.py`의 `analyze_corner` 메서드를 교체:

```python
def analyze_corner(self, image) -> float:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (3, 3), 0)
    h, w = gray.shape
    # 이미지 중앙 영역 집중 분석 (클로즈업 사진이므로 코너가 중앙에 위치)
    cx, cy = w // 4, h // 4
    region = blurred[cy:cy*3, cx:cx*3]
    edges = cv2.Canny(region, 40, 120)
    edge_density = np.count_nonzero(edges) / edges.size
    # Harris corner strength
    harris = cv2.cornerHarris(blurred.astype(np.float32), blockSize=2, ksize=3, k=0.04)
    corner_strength = harris.max() / (harris.mean() + 1e-6)
    # edge_density 0.08+ = 선명(10), 0.04 = 보통(7), 0.01 = 마모(3)
    density_score = min(10.0, max(1.0, edge_density * 120))
    # corner_strength 500+ = 선명, 100 = 보통, 10 = 마모
    strength_score = min(10.0, max(1.0, np.log10(max(corner_strength, 1)) * 3.3))
    return round((density_score * 0.6 + strength_score * 0.4), 1)
```

- [ ] **Step 4: 코너 테스트 통과 확인**

```bash
python -m pytest tests/test_analyzer.py -k "corner" -v
```

Expected: 3 passed

- [ ] **Step 5: 커밋**

```bash
git add grading/analyzer.py grading/tests/test_analyzer.py
git commit -m "feat: OpenCV 코너 마모 분석 구현"
```

---

## Task 4: 표면 스크래치 분석 구현 (TDD)

**Files:**
- Modify: `grading/tests/test_analyzer.py`
- Modify: `grading/analyzer.py`

- [ ] **Step 1: 표면 테스트 추가**

`test_analyzer.py` 하단에 추가:

```python
def make_surface_image(scratches=0):
    """표면 이미지 합성. scratches: 추가할 선형 스크래치 수."""
    img = np.ones((400, 300, 3), dtype=np.uint8) * 100  # 어두운 단색
    for i in range(scratches):
        x1 = np.random.randint(20, 280)
        y1 = np.random.randint(20, 380)
        x2 = x1 + np.random.randint(30, 100)
        y2 = y1 + np.random.randint(-10, 10)
        cv2.line(img, (x1, y1), (min(x2, 299), max(0, min(y2, 399))), (200, 200, 200), 1)
    return img

def test_surface_clean():
    img = make_surface_image(scratches=0)
    score = analyzer.analyze_surface(img)
    assert score >= 8.0, f"스크래치 없는데 점수 낮음: {score}"

def test_surface_scratched():
    np.random.seed(42)
    img = make_surface_image(scratches=15)
    score = analyzer.analyze_surface(img)
    assert score < 9.0, f"스크래치 많은데 점수 높음: {score}"

def test_surface_returns_float():
    img = make_surface_image()
    score = analyzer.analyze_surface(img)
    assert isinstance(score, float)
    assert 1.0 <= score <= 10.0
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
python -m pytest tests/test_analyzer.py -k "surface" -v
```

Expected: FAIL with `NotImplementedError`

- [ ] **Step 3: 표면 분석 구현**

`analyzer.py`의 `analyze_surface` 메서드를 교체:

```python
def analyze_surface(self, image) -> float:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    # 카드 내부만 분석 (가장자리 10% 제외)
    h, w = gray.shape
    margin_y, margin_x = int(h * 0.1), int(w * 0.1)
    interior = gray[margin_y:h-margin_y, margin_x:w-margin_x]
    blurred = cv2.GaussianBlur(interior, (3, 3), 0)
    edges = cv2.Canny(blurred, 25, 75)
    lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=25,
                             minLineLength=15, maxLineGap=4)
    scratch_count = len(lines) if lines is not None else 0
    # 0개 = 10, 5개 = 8, 15개 = 6, 30개 = 3, 50개+ = 1
    score = max(1.0, 10.0 - scratch_count * 0.18)
    return round(min(10.0, score), 1)
```

- [ ] **Step 4: 표면 테스트 통과 확인**

```bash
python -m pytest tests/test_analyzer.py -k "surface" -v
```

Expected: 3 passed

- [ ] **Step 5: 커밋**

```bash
git add grading/analyzer.py grading/tests/test_analyzer.py
git commit -m "feat: OpenCV 표면 스크래치 분석 구현"
```

---

## Task 5: 화이트닝 분석 구현 (TDD)

**Files:**
- Modify: `grading/tests/test_analyzer.py`
- Modify: `grading/analyzer.py`

- [ ] **Step 1: 화이트닝 테스트 추가**

`test_analyzer.py` 하단에 추가:

```python
def make_back_image(whitening_ratio=0.0):
    """카드 뒷면 이미지. whitening_ratio: 0.0=깨끗, 0.3=심한 화이트닝."""
    img = np.zeros((400, 280, 3), dtype=np.uint8)
    # 포켓몬 카드 뒷면: 진한 파란색
    img[:] = (139, 85, 30)  # BGR → 진한 파란색
    if whitening_ratio > 0:
        # 가장자리에 흰색 픽셀 추가
        border = int(min(400, 280) * whitening_ratio)
        img[:border, :] = (240, 240, 240)   # 상단 화이트닝
        img[-border:, :] = (240, 240, 240)  # 하단 화이트닝
    return img

def test_whitening_clean():
    img = make_back_image(whitening_ratio=0.0)
    score, heavy = analyzer.analyze_whitening(img)
    assert score >= 9.0, f"화이트닝 없는데 점수 낮음: {score}"
    assert heavy is False

def test_whitening_heavy():
    img = make_back_image(whitening_ratio=0.15)
    score, heavy = analyzer.analyze_whitening(img)
    assert score < 7.0, f"심한 화이트닝인데 점수 높음: {score}"
    assert heavy is True

def test_whitening_returns_tuple():
    img = make_back_image()
    result = analyzer.analyze_whitening(img)
    assert isinstance(result, tuple) and len(result) == 2
    score, heavy = result
    assert 1.0 <= score <= 10.0
    assert isinstance(heavy, bool)
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
python -m pytest tests/test_analyzer.py -k "whitening" -v
```

Expected: FAIL with `NotImplementedError`

- [ ] **Step 3: 화이트닝 분석 구현**

`analyzer.py`의 `analyze_whitening` 메서드를 교체:

```python
def analyze_whitening(self, image):
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    h, w = hsv.shape[:2]
    margin = max(int(min(h, w) * 0.12), 8)
    regions = [
        hsv[:margin, :],
        hsv[-margin:, :],
        hsv[:, :margin],
        hsv[:, -margin:],
    ]
    total, white = 0, 0
    for region in regions:
        total += region.shape[0] * region.shape[1]
        # 흰색/회색: 채도 낮고 밝기 높음
        mask = cv2.inRange(region, np.array([0, 0, 160]), np.array([180, 40, 255]))
        white += int(mask.sum() / 255)
    ratio = white / total if total > 0 else 0.0
    # 0% = 10, 5% = 8, 15% = 5, 30% = 1
    score = max(1.0, 10.0 - ratio * 60)
    heavy = ratio > 0.08
    return round(min(10.0, score), 1), heavy
```

- [ ] **Step 4: 화이트닝 테스트 통과 확인**

```bash
python -m pytest tests/test_analyzer.py -k "whitening" -v
```

Expected: 3 passed

- [ ] **Step 5: 커밋**

```bash
git add grading/analyzer.py grading/tests/test_analyzer.py
git commit -m "feat: OpenCV 화이트닝 감지 분석 구현"
```

---

## Task 6: 종합 점수 + FastAPI 엔드포인트 완성

**Files:**
- Modify: `grading/analyzer.py`
- Modify: `grading/tests/test_analyzer.py`

- [ ] **Step 1: 종합 점수 테스트 추가**

`test_analyzer.py` 하단에 추가:

```python
def test_full_analyze_returns_result():
    front = make_card_image()
    back = make_back_image()
    corners = [make_corner_image(sharp=True)] * 8
    result = analyzer.analyze(front, back, corners)
    assert hasattr(result, 'total_score')
    assert hasattr(result, 'centering_score')
    assert hasattr(result, 'corner_score')
    assert hasattr(result, 'surface_score')
    assert hasattr(result, 'whitening_score')
    assert hasattr(result, 'heavy_whitening')
    assert 1.0 <= result.total_score <= 10.0

def test_heavy_whitening_penalizes_total():
    front = make_card_image()
    back_clean = make_back_image(whitening_ratio=0.0)
    back_heavy = make_back_image(whitening_ratio=0.2)
    corners = [make_corner_image()] * 8
    result_clean = analyzer.analyze(front, back_clean, corners)
    result_heavy = analyzer.analyze(front, back_heavy, corners)
    assert result_heavy.total_score < result_clean.total_score
```

- [ ] **Step 2: 테스트 실패 확인**

```bash
python -m pytest tests/test_analyzer.py -k "full_analyze or heavy_whitening" -v
```

Expected: FAIL with `NotImplementedError`

- [ ] **Step 3: analyze() 메서드 구현**

`analyzer.py`의 `analyze` 메서드를 교체:

```python
def analyze(self, front, back, corners: list) -> AnalysisResult:
    centering = self.analyze_centering(front)
    corner_scores = [self.analyze_corner(c) for c in corners]
    corner_avg = round(sum(corner_scores) / len(corner_scores), 1)
    surface_front = self.analyze_surface(front)
    surface_back = self.analyze_surface(back)
    surface_avg = round((surface_front + surface_back) / 2, 1)
    whitening_score, heavy = self.analyze_whitening(back)
    # 뒤 모서리 4장 화이트닝도 추가 확인
    back_corner_whitening = [self.analyze_whitening(c)[0] for c in corners[4:]]
    whitening_combined = round((whitening_score + sum(back_corner_whitening) / 4) / 2, 1)
    _, heavy = self.analyze_whitening(back)

    weighted = (
        centering * 0.15 +
        corner_avg * 0.35 +
        surface_avg * 0.25 +
        whitening_combined * 0.25
    )
    if heavy:
        weighted *= 0.85

    total = round(min(10.0, max(1.0, weighted)), 1)

    return AnalysisResult(
        centering_score=centering,
        corner_score=corner_avg,
        surface_score=surface_avg,
        whitening_score=whitening_combined,
        total_score=total,
        heavy_whitening=heavy,
    )
```

- [ ] **Step 4: 전체 테스트 통과 확인**

```bash
python -m pytest tests/test_analyzer.py -v
```

Expected: 모든 테스트 PASS

- [ ] **Step 5: FastAPI 서버 기동 후 health 확인**

```bash
uvicorn main:app --port 8081
curl http://localhost:8081/health
```

Expected: `{"status":"ok"}`

- [ ] **Step 6: 커밋**

```bash
git add grading/
git commit -m "feat: 종합 점수 산출 + FastAPI 분석 엔드포인트 완성"
```

---

## Task 7: DB DDL + Spring Boot 엔티티

**Files:**
- Create: `db/grading_results.sql`
- Create: `back/src/main/java/com/fury/back/domain/grading/GradingResult.java`
- Create: `back/src/main/java/com/fury/back/domain/grading/GradingResultRepository.java`
- Create: `back/src/main/java/com/fury/back/domain/grading/dto/GradingResultDto.java`
- Create: `back/src/main/java/com/fury/back/domain/grading/dto/GradingAnalysisDto.java`

- [ ] **Step 1: DDL 작성 및 실행**

`db/grading_results.sql`:

```sql
CREATE TABLE grading_results (
    result_id       VARCHAR(50)    PRIMARY KEY,
    user_id         VARCHAR(50)    NOT NULL,
    card_id         VARCHAR(50),
    centering_score NUMERIC(3,1)   NOT NULL,
    corner_score    NUMERIC(3,1)   NOT NULL,
    surface_score   NUMERIC(3,1)   NOT NULL,
    whitening_score NUMERIC(3,1)   NOT NULL,
    total_score     NUMERIC(3,1)   NOT NULL,
    heavy_whitening BOOLEAN        NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMP      NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_grading_results_user_id ON grading_results(user_id);
```

```bash
psql -U nightfury -d pokemon_card_db -f /Users/nightfury/work_temp/pokemon_card_app/db/grading_results.sql
```

Expected: CREATE TABLE, CREATE INDEX

- [ ] **Step 2: GradingResult 엔티티 작성**

`GradingResult.java`:

```java
package com.fury.back.domain.grading;

import jakarta.persistence.*;
import lombok.*;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "grading_results")
@Getter @Setter @NoArgsConstructor @AllArgsConstructor @Builder
public class GradingResult {

    @Id
    @Column(name = "result_id", length = 50)
    private String resultId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    @Column(name = "card_id", length = 50)
    private String cardId;

    @Column(name = "centering_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal centeringScore;

    @Column(name = "corner_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal cornerScore;

    @Column(name = "surface_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal surfaceScore;

    @Column(name = "whitening_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal whiteningScore;

    @Column(name = "total_score", nullable = false, precision = 3, scale = 1)
    private BigDecimal totalScore;

    @Column(name = "heavy_whitening", nullable = false)
    private boolean heavyWhitening;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;
}
```

- [ ] **Step 3: GradingResultRepository 작성**

`GradingResultRepository.java`:

```java
package com.fury.back.domain.grading;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface GradingResultRepository extends JpaRepository<GradingResult, String> {
    List<GradingResult> findByUserIdOrderByCreatedAtDesc(String userId);
}
```

- [ ] **Step 4: DTO 작성**

`GradingAnalysisDto.java` (FastAPI 응답 역직렬화):

```java
package com.fury.back.domain.grading.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class GradingAnalysisDto {
    @JsonProperty("centering_score") private BigDecimal centeringScore;
    @JsonProperty("corner_score")    private BigDecimal cornerScore;
    @JsonProperty("surface_score")   private BigDecimal surfaceScore;
    @JsonProperty("whitening_score") private BigDecimal whiteningScore;
    @JsonProperty("total_score")     private BigDecimal totalScore;
    @JsonProperty("heavy_whitening") private boolean heavyWhitening;
}
```

`GradingResultDto.java` (클라이언트 응답):

```java
package com.fury.back.domain.grading.dto;

import lombok.Builder;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data @Builder
public class GradingResultDto {
    private String resultId;
    private String cardId;
    private BigDecimal centeringScore;
    private BigDecimal cornerScore;
    private BigDecimal surfaceScore;
    private BigDecimal whiteningScore;
    private BigDecimal totalScore;
    private boolean heavyWhitening;
    private LocalDateTime createdAt;
}
```

- [ ] **Step 5: 백엔드 빌드 확인**

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/back
./gradlew compileJava
```

Expected: BUILD SUCCESSFUL

- [ ] **Step 6: 커밋**

```bash
git add db/grading_results.sql back/src/main/java/com/fury/back/domain/grading/
git commit -m "feat: grading_results DDL + Spring Boot 엔티티/DTO 추가"
```

---

## Task 8: Spring Boot 서비스 + 컨트롤러

**Files:**
- Create: `back/src/main/java/com/fury/back/domain/grading/GradingService.java`
- Create: `back/src/main/java/com/fury/back/domain/grading/GradingServiceImpl.java`
- Create: `back/src/main/java/com/fury/back/domain/grading/GradingController.java`
- Modify: `back/src/main/resources/application.properties`

- [ ] **Step 1: application.properties에 FastAPI URL 추가**

```properties
grading.service.url=http://localhost:8081
```

- [ ] **Step 2: GradingService 인터페이스 작성**

`GradingService.java`:

```java
package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingResultDto;
import org.springframework.web.multipart.MultipartFile;
import java.util.List;
import java.util.Map;

public interface GradingService {
    ReturnData<GradingResultDto> analyze(Map<String, MultipartFile> photos, String userId, String cardId);
    ReturnData<List<GradingResultDto>> getHistory(String userId);
}
```

- [ ] **Step 3: GradingServiceImpl 작성**

`GradingServiceImpl.java`:

```java
package com.fury.back.domain.grading;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingAnalysisDto;
import com.fury.back.domain.grading.dto.GradingResultDto;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.ByteArrayResource;
import org.springframework.http.*;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestTemplate;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class GradingServiceImpl implements GradingService {

    private final GradingResultRepository repository;
    private final RestTemplate restTemplate;

    @Value("${grading.service.url}")
    private String gradingServiceUrl;

    @Override
    public ReturnData<GradingResultDto> analyze(Map<String, MultipartFile> photos, String userId, String cardId) {
        GradingAnalysisDto analysis = callPythonService(photos);

        GradingResult entity = GradingResult.builder()
                .resultId(IdGenerator.generate())
                .userId(userId)
                .cardId(cardId)
                .centeringScore(analysis.getCenteringScore())
                .cornerScore(analysis.getCornerScore())
                .surfaceScore(analysis.getSurfaceScore())
                .whiteningScore(analysis.getWhiteningScore())
                .totalScore(analysis.getTotalScore())
                .heavyWhitening(analysis.isHeavyWhitening())
                .createdAt(LocalDateTime.now())
                .build();

        repository.save(entity);

        return ReturnData.success(toDto(entity));
    }

    @Override
    public ReturnData<List<GradingResultDto>> getHistory(String userId) {
        List<GradingResultDto> list = repository.findByUserIdOrderByCreatedAtDesc(userId)
                .stream().map(this::toDto).collect(Collectors.toList());
        return ReturnData.success(list);
    }

    private GradingAnalysisDto callPythonService(Map<String, MultipartFile> photos) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.MULTIPART_FORM_DATA);
        MultiValueMap<String, Object> body = new LinkedMultiValueMap<>();
        photos.forEach((name, file) -> {
            try {
                ByteArrayResource resource = new ByteArrayResource(file.getBytes()) {
                    @Override public String getFilename() { return file.getOriginalFilename(); }
                };
                body.add(name, resource);
            } catch (IOException e) {
                throw new RuntimeException("사진 읽기 실패: " + name, e);
            }
        });
        HttpEntity<MultiValueMap<String, Object>> request = new HttpEntity<>(body, headers);
        ResponseEntity<GradingAnalysisDto> response = restTemplate.postForEntity(
                gradingServiceUrl + "/analyze", request, GradingAnalysisDto.class);
        return response.getBody();
    }

    private GradingResultDto toDto(GradingResult e) {
        return GradingResultDto.builder()
                .resultId(e.getResultId())
                .cardId(e.getCardId())
                .centeringScore(e.getCenteringScore())
                .cornerScore(e.getCornerScore())
                .surfaceScore(e.getSurfaceScore())
                .whiteningScore(e.getWhiteningScore())
                .totalScore(e.getTotalScore())
                .heavyWhitening(e.isHeavyWhitening())
                .createdAt(e.getCreatedAt())
                .build();
    }
}
```

- [ ] **Step 4: RestTemplate 빈 등록**

`back/src/main/java/com/fury/back/config/WebMvcConfig.java`에 추가:

```java
@Bean
public RestTemplate restTemplate() {
    return new RestTemplate();
}
```

- [ ] **Step 5: GradingController 작성**

`GradingController.java`:

```java
package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingResultDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@Tag(name = "Grading", description = "카드 등급 예측 API")
@RestController
@RequestMapping("/api/grading")
@RequiredArgsConstructor
public class GradingController {

    private final GradingService gradingService;

    @Operation(summary = "카드 등급 분석", description = "사진 10장을 받아 센터링/코너/표면/화이트닝 항목별 점수와 종합 예상 등급 반환")
    @PostMapping(value = "/analyze", consumes = "multipart/form-data")
    public ReturnData<GradingResultDto> analyze(
            @RequestParam Map<String, MultipartFile> photos,
            @RequestParam String userId,
            @RequestParam(required = false) String cardId) {
        return gradingService.analyze(photos, userId, cardId);
    }

    @Operation(summary = "분석 기록 조회")
    @GetMapping("/history")
    public ReturnData<List<GradingResultDto>> getHistory(@RequestParam String userId) {
        return gradingService.getHistory(userId);
    }
}
```

- [ ] **Step 6: 백엔드 재시작 + 엔드포인트 확인**

```bash
lsof -i :8080 | grep java | awk '{print $2}' | xargs kill -9 2>/dev/null; true
cd /Users/nightfury/work_temp/pokemon_card_app/back && ./gradlew bootRun &
sleep 15
curl -s http://localhost:8080/api/grading/history?userId=test | python3 -m json.tool
```

Expected: `{"status":"success","data":[]}`

- [ ] **Step 7: 커밋**

```bash
git add back/src/main/java/com/fury/back/domain/grading/ back/src/main/resources/application.properties
git commit -m "feat: Spring Boot 그레이딩 서비스 + 컨트롤러 구현"
```

---

## Task 9: Flutter — 하단 탭 채팅 → 등급 교체

**Files:**
- Modify: `front/lib/features/shell/main_shell.dart`
- Modify: `front/lib/core/router/app_router.dart`
- Modify: `front/lib/core/constants/api_constants.dart`

- [ ] **Step 1: api_constants.dart에 grading 경로 추가**

`api_constants.dart`에 추가:

```dart
static const String gradingAnalyze = '/api/grading/analyze';
static const String gradingHistory = '/api/grading/history';
```

- [ ] **Step 2: main_shell.dart 탭 변경**

`_tabs` 리스트와 `_BottomNav`에서 `/chat` → `/grading` 교체:

```dart
static const _tabs = ['/home', '/prices', '/grading', '/profile'];
```

`_NavItem` 채팅 항목을 등급으로 교체:

```dart
_NavItem(icon: Icons.grade_rounded, label: '등급', index: 2, currentIndex: currentIndex, route: '/grading'),
```

- [ ] **Step 3: app_router.dart에 /grading 라우트 추가**

ShellRoute의 routes 안에 추가:

```dart
GoRoute(path: '/grading', builder: (_, __) => const GradingScreen()),
```

상단 import 추가:

```dart
import '../../features/grading/grading_screen.dart';
```

- [ ] **Step 4: 빌드 오류 없는지 확인 (grading_screen.dart 스텁 먼저 생성)**

`front/lib/features/grading/grading_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class GradingScreen extends StatelessWidget {
  const GradingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: Text('등급 예측', style: TextStyle(color: AppColors.textPrimary))),
    );
  }
}
```

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/front
flutter build apk --debug 2>&1 | tail -5
```

Expected: 빌드 오류 없음

- [ ] **Step 5: 커밋**

```bash
git add front/lib/features/shell/main_shell.dart front/lib/core/router/app_router.dart front/lib/core/constants/api_constants.dart front/lib/features/grading/grading_screen.dart
git commit -m "feat: 하단 탭 채팅→등급 교체, 라우터 추가"
```

---

## Task 10: Flutter — 등급 메인 화면 + 10장 촬영

**Files:**
- Modify: `front/lib/features/grading/grading_screen.dart`
- Create: `front/lib/features/grading/grading_capture_screen.dart`

- [ ] **Step 1: grading_screen.dart 완성**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';

class GradingScreen extends StatelessWidget {
  const GradingScreen({super.key});

  static const _steps = [
    ('앞면 전체', '카드 앞면 전체가 나오도록 찍어주세요'),
    ('뒷면 전체', '카드 뒷면 전체가 나오도록 찍어주세요'),
    ('앞 좌상단 모서리', '앞면 왼쪽 위 모서리를 클로즈업해주세요'),
    ('앞 우상단 모서리', '앞면 오른쪽 위 모서리를 클로즈업해주세요'),
    ('앞 좌하단 모서리', '앞면 왼쪽 아래 모서리를 클로즈업해주세요'),
    ('앞 우하단 모서리', '앞면 오른쪽 아래 모서리를 클로즈업해주세요'),
    ('뒤 좌상단 모서리', '뒷면 왼쪽 위 모서리를 클로즈업해주세요'),
    ('뒤 우상단 모서리', '뒷면 오른쪽 위 모서리를 클로즈업해주세요'),
    ('뒤 좌하단 모서리', '뒷면 왼쪽 아래 모서리를 클로즈업해주세요'),
    ('뒤 우하단 모서리', '뒷면 오른쪽 아래 모서리를 클로즈업해주세요'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        title: const Text('등급 예측', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A3A6A), Color(0xFF0D2040)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.blue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.grade_rounded, color: AppColors.blue, size: 36),
                const SizedBox(height: 12),
                const Text('카드 등급 예측',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('사진 10장으로 센터링, 코너, 표면 상태, 화이트닝을 분석해\nPSA/CGC 기준 예상 등급을 알려드립니다.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text('촬영 순서', style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._steps.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: AppColors.blue.withOpacity(0.15), shape: BoxShape.circle),
                  child: Center(child: Text('${e.key + 1}', style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: 10),
                Text(e.value.$1, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14)),
              ],
            ),
          )),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () => context.push('/grading/capture'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('시작하기', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: grading_capture_screen.dart 작성**

```dart
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/theme/app_colors.dart';

class GradingCaptureScreen extends StatefulWidget {
  const GradingCaptureScreen({super.key});
  @override
  State<GradingCaptureScreen> createState() => _GradingCaptureScreenState();
}

class _GradingCaptureScreenState extends State<GradingCaptureScreen> {
  CameraController? _controller;
  bool _cameraReady = false;
  int _step = 0;
  final List<File> _photos = [];

  static const _stepLabels = [
    ('앞면 전체', '카드 앞면 전체가 화면에 꽉 차도록 찍어주세요'),
    ('뒷면 전체', '카드 뒷면 전체가 화면에 꽉 차도록 찍어주세요'),
    ('앞 좌상단', '앞면 왼쪽 위 모서리를 최대한 가깝게 찍어주세요'),
    ('앞 우상단', '앞면 오른쪽 위 모서리를 최대한 가깝게 찍어주세요'),
    ('앞 좌하단', '앞면 왼쪽 아래 모서리를 최대한 가깝게 찍어주세요'),
    ('앞 우하단', '앞면 오른쪽 아래 모서리를 최대한 가깝게 찍어주세요'),
    ('뒤 좌상단', '뒷면 왼쪽 위 모서리를 최대한 가깝게 찍어주세요'),
    ('뒤 우상단', '뒷면 오른쪽 위 모서리를 최대한 가깝게 찍어주세요'),
    ('뒤 좌하단', '뒷면 왼쪽 아래 모서리를 최대한 가깝게 찍어주세요'),
    ('뒤 우하단', '뒷면 오른쪽 아래 모서리를 최대한 가깝게 찍어주세요'),
  ];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;
    _controller = CameraController(cameras.first, ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() => _cameraReady = true);
  }

  Future<void> _capture() async {
    if (_controller == null || !_cameraReady) return;
    final xfile = await _controller!.takePicture();
    _photos.add(File(xfile.path));
    if (_step < 9) {
      setState(() => _step++);
    } else {
      await _controller!.dispose();
      if (mounted) context.push('/grading/result', extra: {'photos': _photos});
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (label, hint) = _stepLabels[_step];
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_cameraReady && _controller != null)
            Positioned.fill(child: CameraPreview(_controller!)),
          // 상단 진행 표시
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => context.pop()),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: (_step + 1) / 10,
                            backgroundColor: Colors.white24,
                            valueColor: const AlwaysStoppedAnimation(AppColors.blue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('${_step + 1}/10', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(hint, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
          // 촬영 버튼
          Positioned(
            bottom: 48, left: 0, right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _capture,
                child: Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 4),
                    color: Colors.white24,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: app_router.dart에 /grading/capture, /grading/result 라우트 추가**

```dart
import '../../features/grading/grading_capture_screen.dart';
import '../../features/grading/grading_result_screen.dart';
```

```dart
GoRoute(path: '/grading/capture', builder: (_, __) => const GradingCaptureScreen()),
GoRoute(
  path: '/grading/result',
  builder: (context, state) {
    final extra = state.extra as Map<String, dynamic>;
    return GradingResultScreen(photos: extra['photos'] as List<File>);
  },
),
```

- [ ] **Step 4: grading_result_screen.dart 스텁 생성 (빌드 오류 방지)**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

class GradingResultScreen extends StatelessWidget {
  final List<File> photos;
  const GradingResultScreen({super.key, required this.photos});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(child: CircularProgressIndicator(color: AppColors.blue)),
    );
  }
}
```

- [ ] **Step 5: 빌드 확인**

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/front
flutter build apk --debug 2>&1 | tail -5
```

Expected: 오류 없음

- [ ] **Step 6: 커밋**

```bash
git add front/lib/features/grading/ front/lib/core/router/app_router.dart
git commit -m "feat: 등급 메인화면 + 10장 촬영 화면 구현"
```

---

## Task 11: Flutter — 결과 화면

**Files:**
- Modify: `front/lib/features/grading/grading_result_screen.dart`

- [ ] **Step 1: grading_result_screen.dart 완성**

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/network/api_client.dart';
import '../../core/constants/api_constants.dart';
import '../../core/storage/token_storage.dart';
import '../../core/theme/app_colors.dart';

class GradingResultScreen extends StatefulWidget {
  final List<File> photos;
  const GradingResultScreen({super.key, required this.photos});
  @override
  State<GradingResultScreen> createState() => _GradingResultScreenState();
}

class _GradingResultScreenState extends State<GradingResultScreen> {
  Map<String, dynamic>? _result;
  bool _loading = true;
  String? _error;

  static const _photoKeys = [
    'front', 'back',
    'corner_front_tl', 'corner_front_tr', 'corner_front_bl', 'corner_front_br',
    'corner_back_tl', 'corner_back_tr', 'corner_back_bl', 'corner_back_br',
  ];

  @override
  void initState() {
    super.initState();
    _analyze();
  }

  Future<void> _analyze() async {
    try {
      // userId는 /api/users/me 로 조회 (TokenStorage는 JWT만 저장)
      String userId = 'guest';
      try {
        final userRes = await ApiClient.get('/api/users/me');
        userId = (userRes['data'] as Map<String, dynamic>?)?['userId'] as String? ?? 'guest';
      } catch (_) {}
      final files = <String, File>{};
      for (int i = 0; i < widget.photos.length; i++) {
        files[_photoKeys[i]] = widget.photos[i];
      }
      final res = await ApiClient.postMultipart(
        ApiConstants.gradingAnalyze,
        files: files,
        fields: {'userId': userId},
      );
      if (mounted) setState(() { _result = res['data']; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg, elevation: 0,
        title: const Text('분석 결과', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CircularProgressIndicator(color: AppColors.blue),
              SizedBox(height: 16),
              Text('사진 분석 중...', style: TextStyle(color: AppColors.textSecondary)),
            ]))
          : _error != null
              ? Center(child: Text('분석 실패: $_error', style: const TextStyle(color: AppColors.red)))
              : _buildResult(),
    );
  }

  Widget _buildResult() {
    final r = _result!;
    final total = (r['totalScore'] as num).toDouble();
    final heavy = r['heavyWhitening'] as bool? ?? false;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // 종합 점수 카드
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A3A6A), Color(0xFF0D2040)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.blue.withOpacity(0.3)),
          ),
          child: Column(children: [
            const Text('예상 등급', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 8),
            Text(total.toStringAsFixed(1),
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 56, fontWeight: FontWeight.bold)),
            Text('/ 10.0', style: TextStyle(color: AppColors.textMuted, fontSize: 16)),
            if (heavy) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: AppColors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                child: const Text('⚠ 심한 화이트닝 감지됨', style: TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            ],
          ]),
        ),
        const SizedBox(height: 20),
        // 항목별 점수
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(children: [
            _buildScoreRow('센터링', r['centeringScore']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('코너', r['cornerScore']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('표면', r['surfaceScore']),
            const Divider(color: AppColors.divider, height: 20),
            _buildScoreRow('화이트닝', r['whiteningScore']),
          ]),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => context.go('/grading'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.blue,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('다시 분석하기', style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildScoreRow(String label, dynamic scoreRaw) {
    final score = (scoreRaw as num).toDouble();
    final color = score >= 9.0 ? AppColors.green : score >= 7.0 ? AppColors.blue : AppColors.red;
    return Row(children: [
      SizedBox(width: 80, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14))),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: score / 10.0,
            minHeight: 8,
            backgroundColor: AppColors.divider,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text(score.toStringAsFixed(1), style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
    ]);
  }
}
```

- [ ] **Step 2: ApiClient에 postMultipart 메서드 추가**

`front/lib/core/network/api_client.dart`에 추가 (기존 Dio 기반으로 작성):

```dart
static Future<Map<String, dynamic>> postMultipart(
  String path, {
  required Map<String, File> files,
  Map<String, String> fields = const {},
}) async {
  final formData = FormData();
  fields.forEach((k, v) => formData.fields.add(MapEntry(k, v)));
  for (final entry in files.entries) {
    formData.files.add(MapEntry(
      entry.key,
      await MultipartFile.fromFile(entry.value.path, filename: entry.key),
    ));
  }
  final res = await _dio.post(path, data: formData);
  return res.data;
}
```

상단 import에 `dart:io` 추가:
```dart
import 'dart:io';
```

- [ ] **Step 3: AppColors에 green 색상 확인/추가**

`front/lib/core/theme/app_colors.dart`에 없으면 추가:

```dart
static const Color green = Color(0xFF34C759);
```

- [ ] **Step 4: 전체 빌드 확인**

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/front
flutter build apk --debug 2>&1 | tail -10
```

Expected: BUILD SUCCESSFUL

- [ ] **Step 5: 커밋**

```bash
git add front/lib/features/grading/grading_result_screen.dart front/lib/core/network/api_client.dart front/lib/core/theme/app_colors.dart
git commit -m "feat: 등급 결과 화면 구현"
```

---

## Task 12: 통합 확인 + 거래/채팅 진입점 정리

**Files:**
- Modify: `front/lib/features/profile/profile_screen.dart`

- [ ] **Step 1: profile_screen.dart에서 판매 항목 메뉴 제거**

`profile_screen.dart`의 `_buildSection('내 활동', [...])` 에서 판매 항목 줄 제거:

```dart
// 제거할 줄:
_buildMenuItem(Icons.sell_rounded, '판매 항목',
    () => context.push('/my-trades', extra: {'sellerId': _userId})),
```

- [ ] **Step 2: FastAPI + Spring Boot + Flutter 동시 기동 확인**

터미널 1 — FastAPI:
```bash
cd /Users/nightfury/work_temp/pokemon_card_app/grading
source venv/bin/activate
uvicorn main:app --port 8081
```

터미널 2 — Spring Boot:
```bash
cd /Users/nightfury/work_temp/pokemon_card_app/back
./gradlew bootRun
```

- [ ] **Step 3: Flutter 앱 기동 + 등급 탭 진입 확인**

```bash
cd /Users/nightfury/work_temp/pokemon_card_app/front
flutter run
```

확인 항목:
- 하단 탭 "등급" 표시됨
- 시작하기 → 10단계 촬영 화면 진입
- 채팅 탭 없어짐
- 프로필에서 판매 항목 없어짐

- [ ] **Step 4: 최종 커밋**

```bash
git add front/lib/features/profile/profile_screen.dart
git commit -m "feat: 거래/채팅 진입점 제거, 초기 버전 정리"
```
