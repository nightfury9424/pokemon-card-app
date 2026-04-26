import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import cv2
import numpy as np
import pytest
from analyzer import GradingAnalyzer

def make_card_image(width=400, height=560, lr_offset=0, tb_offset=0):
    """카드 이미지 합성. lr_offset>0이면 좌측 여백이 더 큼 (오른쪽 치우침)."""
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


def make_corner_image(sharp=True):
    """코너 이미지 합성. sharp=True면 선명한 코너, False면 마모."""
    img = np.ones((150, 150, 3), dtype=np.uint8) * 180
    if sharp:
        cv2.rectangle(img, (10, 10), (140, 140), (30, 30, 30), 2)
        cv2.line(img, (10, 10), (30, 10), (0, 0, 0), 3)
        cv2.line(img, (10, 10), (10, 30), (0, 0, 0), 3)
    else:
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


def make_surface_image(scratches=0):
    img = np.ones((400, 300, 3), dtype=np.uint8) * 100
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


def make_back_image(whitening_ratio=0.0):
    img = np.zeros((400, 280, 3), dtype=np.uint8)
    img[:] = (139, 85, 30)  # BGR 진한 파란색
    if whitening_ratio > 0:
        border = int(min(400, 280) * whitening_ratio)
        img[:border, :] = (240, 240, 240)
        img[-border:, :] = (240, 240, 240)
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
