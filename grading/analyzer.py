import cv2
import numpy as np
from models import AnalysisResult


class GradingAnalyzer:

    def analyze_centering(self, image) -> float:
        h_img, w_img = image.shape[:2]
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 30, 100)
        contours, _ = cv2.findContours(edges, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)

        if not contours:
            return 5.0

        rects = []
        for c in contours:
            if cv2.contourArea(c) < 100:
                continue
            x, y, w, h = cv2.boundingRect(c)
            rects.append((cv2.contourArea(c), x, y, w, h))

        rects.sort(reverse=True)

        if not rects:
            return 5.0

        # Deduplicate near-identical rects (double-edge artifact from Canny)
        unique_rects = [rects[0]]
        for r in rects[1:]:
            prev = unique_rects[-1]
            if (abs(r[0] - prev[0]) / max(prev[0], 1) < 0.02
                    and abs(r[1] - prev[1]) <= 2
                    and abs(r[2] - prev[2]) <= 2):
                continue
            unique_rects.append(r)

        outer = unique_rects[0]
        oa, ox, oy, ow, oh = outer

        def compute_score(left_m, right_m, top_m, bottom_m):
            lr_total = left_m + right_m
            tb_total = top_m + bottom_m
            lr_ratio = left_m / lr_total if lr_total > 0 else 0.5
            tb_ratio = top_m / tb_total if tb_total > 0 else 0.5
            lr_dev = abs(lr_ratio - 0.5)
            tb_dev = abs(tb_ratio - 0.5)
            lr_score = max(1.0, 10.0 - (lr_dev / 0.05) * 1.5)
            tb_score = max(1.0, 10.0 - (tb_dev / 0.05) * 1.5)
            return round(min(10.0, (lr_score + tb_score) / 2), 1)

        if len(unique_rects) >= 2:
            # Find inner rect: must be meaningfully smaller than outer
            inner = None
            for r in unique_rects[1:]:
                if r[0] < outer[0] * 0.9:
                    inner = r
                    break
            if inner is None:
                inner = unique_rects[1]
            ia, ix, iy, iw, ih = inner
            left_m = ix - ox
            right_m = (ox + ow) - (ix + iw)
            top_m = iy - oy
            bottom_m = (oy + oh) - (iy + ih)
            return compute_score(left_m, right_m, top_m, bottom_m)
        else:
            # Fallback: find inner content via color thresholding
            roi = image[oy:oy + oh, ox:ox + ow]
            gray_roi = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
            _, dark_mask = cv2.threshold(gray_roi, 160, 255, cv2.THRESH_BINARY_INV)
            kernel = np.ones((5, 5), np.uint8)
            dark_mask = cv2.erode(dark_mask, kernel, iterations=1)
            dark_contours, _ = cv2.findContours(
                dark_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE
            )
            if dark_contours:
                dark_f = [
                    (cv2.contourArea(c), cv2.boundingRect(c))
                    for c in dark_contours
                    if cv2.contourArea(c) > 100
                ]
                dark_f.sort(reverse=True)
                if dark_f:
                    _, (ix, iy, iw, ih) = dark_f[0]
                    left_m = ix
                    right_m = ow - (ix + iw)
                    top_m = iy
                    bottom_m = oh - (iy + ih)
                    return compute_score(left_m, right_m, top_m, bottom_m)
            return 8.0

    def analyze_corner(self, image) -> float:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        blurred = cv2.GaussianBlur(gray, (3, 3), 0)
        edges = cv2.Canny(blurred, 30, 100)
        edge_density = np.count_nonzero(edges) / edges.size
        # 선명한 코너: 명확한 직선 엣지 많음(높은 density)
        # 마모된 코너: 라운딩으로 엣지 적음(낮은 density)
        score = min(10.0, max(1.0, edge_density * 200))
        return round(score, 1)

    def analyze_surface(self, image) -> float:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape
        margin_y, margin_x = int(h * 0.1), int(w * 0.1)
        interior = gray[margin_y:h-margin_y, margin_x:w-margin_x]
        blurred = cv2.GaussianBlur(interior, (3, 3), 0)
        edges = cv2.Canny(blurred, 25, 75)
        lines = cv2.HoughLinesP(edges, 1, np.pi / 180, threshold=25,
                                 minLineLength=15, maxLineGap=4)
        scratch_count = len(lines) if lines is not None else 0
        score = max(1.0, 10.0 - scratch_count * 0.18)
        return round(min(10.0, score), 1)

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
            mask = cv2.inRange(region, np.array([0, 0, 160]), np.array([180, 40, 255]))
            white += int(mask.sum() / 255)
        ratio = white / total if total > 0 else 0.0
        score = max(1.0, 10.0 - ratio * 60)
        heavy = ratio > 0.08
        return round(min(10.0, score), 1), heavy

    def analyze(self, front, back, corners: list) -> AnalysisResult:
        centering = self.analyze_centering(front)
        corner_scores = [self.analyze_corner(c) for c in corners]
        corner_avg = round(sum(corner_scores) / len(corner_scores), 1)
        surface_front = self.analyze_surface(front)
        surface_back = self.analyze_surface(back)
        surface_avg = round((surface_front + surface_back) / 2, 1)
        whitening_score, heavy = self.analyze_whitening(back)
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
