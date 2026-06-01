from typing import Any, Dict, List, Optional, Tuple

from pydantic import BaseModel, Field


class DeductionReason(BaseModel):
    """감점 사유 — 결과 화면 핵심 (요약 카드 + 탭 상세). spec §4."""
    id: str
    type: str
    label: str
    side: str
    position: str = ""
    severity: str = "minor"
    confidence: float = 1.0
    penalty: float = 0.0
    bbox: Optional[Tuple[float, float, float, float]] = None
    explanation: str = ""


class DefectRegion(BaseModel):
    """이미지 overlay 용 시각화 전용. spec §4."""
    type: str
    bbox: Tuple[float, float, float, float]
    side: str
    color: str = "#E74C3C"


class AnalysisResult(BaseModel):
    centering_score: float
    centering_ratio: str = ""
    detection_confidence: float = 1.0
    corner_score: float
    surface_score: float
    whitening_score: float
    edge_score: float = 0.0
    total_score: float
    heavy_whitening: bool
    centering_detail: str = ""
    corner_detail: str = ""
    surface_detail: str = ""
    whitening_detail: str = ""
    edge_detail: str = ""

    weighted_score: float = 0.0
    total_score_display: float = 0.0
    grade: str = "C"
    grade_color: str = "#95A5A6"

    deduction_reasons: List[DeductionReason] = Field(default_factory=list)
    defect_regions: List[DefectRegion] = Field(default_factory=list)
    has_major_defect: bool = False

    retake_required: bool = False
    retake_reason: str = ""
    capture_quality: str = "good"

    screen_suspected: bool = False
    screen_suspect_reason: str = ""

    # === P0-1 evidence layer (Phase 2-C) ===
    # P0-fix-1: card_bbox + corner_regions 가 front + back 각각 nested.
    # back overlay 가 front cardBbox 위에 그려져 카드 밖에 표시되는 mismatch 해결.
    # {"front": {"x","y","w","h"}, "back": {"x","y","w","h"}} — 각 사진 좌표계 0~1
    card_bbox: Optional[Dict[str, Any]] = None
    # 카드 내부 print border 4 line (front 의 warp 후 카드 좌표계, normalized 0~1).
    # {"left_x", "right_x", "top_y", "bottom_y"}
    centering_lines: Optional[Dict[str, float]] = None
    centering_confidence: float = 0.0
    # "detected" | "partial" | "fallback"
    centering_source: str = "fallback"
    # P0-fix-1: front + back 각각 4 corner bbox (사진 좌표계 0~1).
    # {"front": {"top_left":{...}, ...}, "back": {"top_left":{...}, ...}}
    corner_regions: Optional[Dict[str, Any]] = None
    # 등급 강등 trace — weakest-link 사용자 납득.
    grade_decision_trace: Optional[Dict[str, Any]] = None
    # 향후 evidence/debug 확장용 (P1 mask URL 등).
    extra: Dict[str, Any] = Field(default_factory=dict)
