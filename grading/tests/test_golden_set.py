"""Golden image regression test — Phase 2-A Step 4.

실제 폰 촬영 이미지 기반 안정성 회귀 테스트.
fixture 비어있으면 skip. 이미지 + expected.json 있으면 자동 회귀.

폴더 구조: tests/fixtures/{card_id}/expected.json + *.jpg

앱 호출 조건과 동일 — frame_hint 전달 (Flutter _normalizedFrameRect() 와 일치).
"""
import json
import os
import sys
from pathlib import Path

import cv2
import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from analyzer import GradingAnalyzer

FIXTURES_DIR = Path(__file__).parent / "fixtures"

# Flutter capture_screen 의 _normalizedFrameRect() 와 일치:
#   _frameWidthRatio = 0.65
#   _frameAspect = 63 / 88
#   frameH = 0.65 / (63/88) ≈ 0.9079
#   frameX = (1 - 0.65) / 2 = 0.175
#   frameY = (1 - 0.9079) / 2 ≈ 0.046
DEFAULT_FRAME_HINT = (0.175, 0.046, 0.65, 0.908)


def _collect_fixture_cases():
    """fixtures/ 안의 모든 card_id 폴더에서 expected.json 의 shots 펼침."""
    cases = []
    if not FIXTURES_DIR.exists():
        return cases
    for card_dir in sorted(FIXTURES_DIR.iterdir()):
        if not card_dir.is_dir():
            continue
        expected_path = card_dir / "expected.json"
        if not expected_path.exists():
            continue
        try:
            with open(expected_path, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            continue
        for i, shot in enumerate(data.get("shots", [])):
            front = card_dir / shot.get("front", "")
            back = card_dir / shot.get("back", "")
            if not front.exists() or not back.exists():
                continue
            hint_raw = shot.get("frame_hint") or data.get("frame_hint")
            if hint_raw and len(hint_raw) == 4:
                frame_hint = tuple(float(x) for x in hint_raw)
            else:
                frame_hint = DEFAULT_FRAME_HINT
            cases.append({
                "card_id": data.get("card_id", card_dir.name),
                "card_name": data.get("card_name", card_dir.name),
                "shot_index": i,
                "front_path": str(front),
                "back_path": str(back),
                "expected_total": float(shot.get("expected_total", 0)),
                "tolerance": float(shot.get("tolerance", 0.5)),
                "notes": shot.get("notes", ""),
                "frame_hint": frame_hint,
            })
    return cases


_FIXTURE_CASES = _collect_fixture_cases()


_CASE_IDS = [f"{c['card_id']}_shot{c['shot_index']}" for c in _FIXTURE_CASES]


@pytest.mark.skipif(
    not _FIXTURE_CASES,
    reason="fixtures/ 비어있음. 실제 카드 이미지 drop 후 재실행",
)
@pytest.mark.parametrize("case", _FIXTURE_CASES, ids=_CASE_IDS)
def test_golden_score_within_tolerance(case):
    """각 fixture shot 의 expected_total 대비 변동폭 ≤ tolerance."""
    front = cv2.imread(case["front_path"])
    back = cv2.imread(case["back_path"])
    assert front is not None, f"front load failed: {case['front_path']}"
    assert back is not None, f"back load failed: {case['back_path']}"

    analyzer = GradingAnalyzer()
    # 앱과 동일 조건 — frame_hint + debug=True (/tmp/grading_debug/ 자동 저장)
    result = analyzer.analyze(
        front, back, frame_hint=case["frame_hint"], debug=True)

    diff = abs(result.total_score - case["expected_total"])
    assert diff <= case["tolerance"], (
        f"{case['card_id']} shot{case['shot_index']} "
        f"expected={case['expected_total']:.1f} actual={result.total_score:.1f} "
        f"diff={diff:.2f} > tol={case['tolerance']:.2f}\n"
        f"  notes: {case['notes']}\n"
        f"  retake={result.retake_required} reason={result.retake_reason}\n"
        f"  grade={result.grade}\n"
        f"  hint: /tmp/grading_debug/ 의 최신 세션 분석"
    )


@pytest.mark.skipif(
    not _FIXTURE_CASES,
    reason="fixtures/ 비어있음",
)
def test_golden_reproducibility_across_shots():
    """같은 card_id 의 모든 shot 점수 = 변동폭 ≤ 0.5 (모두 같은 카드라 비슷해야)."""
    by_card = {}
    for c in _FIXTURE_CASES:
        by_card.setdefault(c["card_id"], []).append(c)
    for card_id, cases in by_card.items():
        if len(cases) < 2:
            continue
        scores = []
        analyzer = GradingAnalyzer()
        for c in cases:
            front = cv2.imread(c["front_path"])
            back = cv2.imread(c["back_path"])
            r = analyzer.analyze(front, back, frame_hint=c["frame_hint"])
            if not r.retake_required:
                scores.append(r.total_score)
        if len(scores) < 2:
            continue
        spread = max(scores) - min(scores)
        assert spread <= 1.0, (
            f"{card_id}: 같은 카드 다른 촬영 변동폭 {spread:.2f} > 1.0\n"
            f"  scores: {scores}"
        )
