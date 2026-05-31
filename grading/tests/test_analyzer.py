import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import cv2
import numpy as np
import pytest
from analyzer import GradingAnalyzer

def make_card_image(width=400, height=560, lr_offset=0, tb_offset=0):
    """카드 이미지 합성. lr_offset>0이면 좌측 여백이 더 큼 (오른쪽 치우침).
    실 사진 texture 시뮬레이션 위해 noise 추가 (Laplacian variance 확보 → blur detect 회피)."""
    img = np.ones((height, width, 3), dtype=np.uint8) * 200
    margin = int(min(width, height) * 0.08)
    left = margin + lr_offset
    right = width - margin + lr_offset
    top = margin + tb_offset
    bottom = height - margin + tb_offset
    left = max(5, min(left, width - 5))
    right = max(left + 10, min(right, width - 5))
    top = max(5, min(top, height - 5))
    bottom = max(top + 10, min(bottom, height - 5))
    cv2.rectangle(img, (left, top), (right, bottom), (50, 50, 150), -1)
    cv2.rectangle(img, (2, 2), (width - 2, height - 2), (30, 30, 30), 3)
    rng = np.random.RandomState(0)
    noise = rng.randint(-18, 18, (height, width, 3), dtype=np.int16)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    return img

analyzer = GradingAnalyzer()


@pytest.fixture(autouse=True)
def reset_analyzer_state():
    """analyzer 내부 cache/warped state 가 test 간 leak 되지 않도록 reset.
    cache_key=id(image) 가 GC 재사용으로 다른 test 의 image 와 충돌 가능."""
    analyzer._rect_cache = {}
    analyzer._warped_front = None
    analyzer._warped_back = None
    analyzer._front_image_id = None
    analyzer._back_image_id = None
    yield

def test_centering_perfect():
    img = make_card_image(lr_offset=0, tb_offset=0)
    score, detail, ratio = analyzer.analyze_centering(img)
    assert score >= 9.0, f"완벽한 센터링인데 점수가 낮음: {score}"

def test_centering_off():
    img = make_card_image(lr_offset=30, tb_offset=0)
    score, detail, ratio = analyzer.analyze_centering(img)
    assert score < 9.0, f"치우친 센터링인데 점수가 높음: {score}"

def test_centering_returns_float():
    img = make_card_image()
    score, detail, ratio = analyzer.analyze_centering(img)
    assert isinstance(score, float)
    assert 1.0 <= score <= 10.0


def make_corner_image(sharp=True):
    """코너 이미지 합성. sharp=True면 선명한 코너, False면 마모.
    마모 = tip 영역(상단 20%) 백화 + 흐림 — analyzer.analyze_corner 가
    HSV white_mask + Laplacian variance 로 감지하는 신호와 일치."""
    img = np.ones((150, 150, 3), dtype=np.uint8) * 180
    if sharp:
        cv2.rectangle(img, (10, 10), (140, 140), (30, 30, 30), 2)
        cv2.line(img, (10, 10), (30, 10), (0, 0, 0), 3)
        cv2.line(img, (10, 10), (10, 30), (0, 0, 0), 3)
    else:
        img[:30, :30] = (250, 250, 250)
        img = cv2.GaussianBlur(img, (5, 5), 0)
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


def make_surface_image(scratches=0):
    """analyze_surface 는 border(5%) 영역 Laplacian std 만 측정 →
    절반 스크래치를 border 영역에 강제 + 굵기 3 + 고대비 색으로 강화."""
    img = np.ones((400, 300, 3), dtype=np.uint8) * 100
    h, w = img.shape[:2]
    bh = max(2, int(h * 0.05))
    bw = max(2, int(w * 0.05))
    for i in range(scratches):
        if i % 2 == 0:
            edge = ['top', 'bottom', 'left', 'right'][i // 2 % 4]
            if edge == 'top':
                x1, y1 = np.random.randint(20, w - 20), np.random.randint(0, bh)
                x2, y2 = x1 + np.random.randint(30, 100), y1 + np.random.randint(-2, 2)
            elif edge == 'bottom':
                x1, y1 = np.random.randint(20, w - 20), h - 1 - np.random.randint(0, bh)
                x2, y2 = x1 + np.random.randint(30, 100), y1 + np.random.randint(-2, 2)
            elif edge == 'left':
                x1, y1 = np.random.randint(0, bw), np.random.randint(20, h - 20)
                x2, y2 = x1 + np.random.randint(-2, 2), y1 + np.random.randint(30, 100)
            else:
                x1, y1 = w - 1 - np.random.randint(0, bw), np.random.randint(20, h - 20)
                x2, y2 = x1 + np.random.randint(-2, 2), y1 + np.random.randint(30, 100)
        else:
            x1 = np.random.randint(0, w)
            y1 = np.random.randint(0, h)
            x2 = x1 + np.random.randint(30, 100)
            y2 = y1 + np.random.randint(-10, 10)
        cv2.line(img, (x1, y1),
                 (max(0, min(x2, w - 1)), max(0, min(y2, h - 1))),
                 (250, 250, 250), 3)
    return img

def test_surface_clean():
    img = make_surface_image(scratches=0)
    score, lap_std = analyzer.analyze_surface(img)
    assert score >= 8.0, f"스크래치 없는데 점수 낮음: {score}"

def test_surface_scratched():
    np.random.seed(42)
    img = make_surface_image(scratches=15)
    score, lap_std = analyzer.analyze_surface(img)
    assert score < 9.0, f"스크래치 많은데 점수 높음: {score}"

def test_surface_returns_float():
    img = make_surface_image()
    score, lap_std = analyzer.analyze_surface(img)
    assert isinstance(score, float)
    assert 1.0 <= score <= 10.0


def make_back_image(whitening_ratio=0.0):
    img = np.zeros((400, 280, 3), dtype=np.uint8)
    img[:] = (139, 85, 30)  # BGR 진한 파란색
    rng = np.random.RandomState(1)
    noise = rng.randint(-18, 18, (400, 280, 3), dtype=np.int16)
    img = np.clip(img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    if whitening_ratio > 0:
        border = int(min(400, 280) * whitening_ratio)
        img[:border, :] = (240, 240, 240)
        img[-border:, :] = (240, 240, 240)
    return img

def test_whitening_clean():
    img = make_back_image(whitening_ratio=0.0)
    score, heavy, ratio = analyzer.analyze_whitening(img)
    assert score >= 9.0, f"화이트닝 없는데 점수 낮음: {score}"
    assert heavy is False

def test_whitening_heavy():
    img = make_back_image(whitening_ratio=0.15)
    score, heavy, ratio = analyzer.analyze_whitening(img)
    assert score < 7.0, f"심한 화이트닝인데 점수 높음: {score}"
    assert heavy is True

def test_whitening_returns_tuple():
    img = make_back_image()
    result = analyzer.analyze_whitening(img)
    assert isinstance(result, tuple) and len(result) == 3
    score, heavy, ratio = result
    assert 1.0 <= score <= 10.0
    assert isinstance(heavy, bool)
    assert 0.0 <= ratio <= 1.0


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


# === Phase 2 Day 1 신규 — 9단계 등급 cap (spec § 3 케이스 검증) ===

def _weighted_sum(metrics):
    return sum(metrics[k] * GradingAnalyzer._WEIGHTS[k] for k in metrics)

def test_grade_case_C_floor_metric():
    """spec § 3 case 1: 9/9/9/1/9 → weighted 7.0, min 1.0, major TRUE → C"""
    metrics = {"centering": 9.0, "corner": 9.0, "surface": 9.0, "whitening": 1.0, "edge": 9.0}
    weighted = _weighted_sum(metrics)
    assert weighted == pytest.approx(7.0, abs=0.01)
    has_major = GradingAnalyzer.has_major_defect(metrics, [])
    assert has_major is True
    grade, color = GradingAnalyzer.calculate_grade(weighted, metrics, has_major)
    assert grade == "C", f"expected C, got {grade} (weighted={weighted}, min={min(metrics.values())})"
    assert color == "#95A5A6"

def test_grade_case_S_minus_low_min_metric():
    """spec § 3 case 2: 10/10/10/8/10 → min 8.0 → S- (weighted 충분해도 min cap)"""
    metrics = {"centering": 10.0, "corner": 10.0, "surface": 10.0, "whitening": 8.0, "edge": 10.0}
    weighted = _weighted_sum(metrics)
    assert weighted >= 8.5
    has_major = GradingAnalyzer.has_major_defect(metrics, [])
    assert has_major is False
    grade, color = GradingAnalyzer.calculate_grade(weighted, metrics, has_major)
    assert grade == "S-", f"expected S-, got {grade} (weighted={weighted}, min={min(metrics.values())})"

def test_grade_case_S_plus_high_uniform():
    """spec § 3 case 3: 9.7/9.5/9.6/9.4/9.5 → weighted ≥9.5, min 9.4 → S+"""
    metrics = {"centering": 9.7, "corner": 9.5, "surface": 9.6, "whitening": 9.4, "edge": 9.5}
    weighted = _weighted_sum(metrics)
    assert weighted >= 9.5
    has_major = GradingAnalyzer.has_major_defect(metrics, [])
    assert has_major is False
    grade, color = GradingAnalyzer.calculate_grade(weighted, metrics, has_major)
    assert grade == "S+", f"expected S+, got {grade} (weighted={weighted}, min={min(metrics.values())})"
    assert color == "#FFD700"

def test_grade_S_demoted_by_has_major():
    """S+/S 는 has_major=True 시 강등 (spec § 3)"""
    metrics = {"centering": 9.7, "corner": 9.5, "surface": 9.6, "whitening": 9.4, "edge": 9.5}
    weighted = _weighted_sum(metrics)
    grade, _ = GradingAnalyzer.calculate_grade(weighted, metrics, has_major=True)
    assert grade not in ("S+", "S"), f"S+/S should be demoted on has_major, got {grade}"


# === Retake 신호 (사용자 design — 분석 불가능 시만 재촬영) ===

def test_retake_required_on_blank_image():
    """단색 / 카드 외곽 detect 실패 = retake_required True"""
    blank = np.zeros((100, 100, 3), dtype=np.uint8)
    result = analyzer.analyze(blank, blank, corners=[make_corner_image()] * 8)
    assert result.retake_required is True
    assert result.capture_quality == "bad"
    assert result.retake_reason != ""

def test_retake_not_required_on_valid_card():
    """정상 카드 이미지 = retake_required False"""
    front = make_card_image()
    back = make_back_image()
    corners = [make_corner_image()] * 8
    result = analyzer.analyze(front, back, corners)
    assert result.retake_required is False
    assert result.capture_quality in ("good", "warning")
