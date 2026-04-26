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
