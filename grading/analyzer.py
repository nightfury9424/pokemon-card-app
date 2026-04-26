import cv2
import numpy as np
from models import AnalysisResult

class GradingAnalyzer:
    def analyze(self, front, back, corners: list) -> AnalysisResult:
        raise NotImplementedError
