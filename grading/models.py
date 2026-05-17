from pydantic import BaseModel

class AnalysisResult(BaseModel):
    centering_score: float
    centering_ratio: str = ""
    detection_confidence: float = 1.0
    corner_score: float
    surface_score: float
    whitening_score: float
    total_score: float
    heavy_whitening: bool
    centering_detail: str = ""
    corner_detail: str = ""
    surface_detail: str = ""
    whitening_detail: str = ""
