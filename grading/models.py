from typing import List, Optional, Tuple

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
