from typing import List

import cv2
import numpy as np
from models import AnalysisResult, DeductionReason, DefectRegion


class GradingAnalyzer:
    CARD_WIDTH = 630
    CARD_HEIGHT = 880
    CARD_RATIO = 63 / 88

    # spec § 3 — 9단계 등급 (등급, weighted_threshold, min_metric_threshold, hex_color)
    _GRADE_TABLE = (
        ("S+", 9.5, 9.0, "#FFD700"),
        ("S",  9.0, 8.5, "#9B59B6"),
        ("S-", 8.5, 8.0, "#BB8FCE"),
        ("A+", 8.0, 7.0, "#3498DB"),
        ("A",  7.0, 6.0, "#5DADE2"),
        ("A-", 6.0, 5.0, "#85C1E2"),
        ("B+", 5.0, 4.0, "#27AE60"),
        ("B",  4.0, 3.0, "#7DCEA0"),
    )
    _DEFAULT_GRADE = ("C", "#95A5A6")

    # spec § 3 — weighted 가중치 (case 1 9/9/9/1/9 = 7.0 정확 일치 검증)
    _WEIGHTS = {
        "centering": 0.10,
        "corner":    0.30,
        "surface":   0.25,
        "whitening": 0.25,
        "edge":      0.10,
    }

    def __init__(self):
        self._warped_front = None
        self._warped_back = None
        self._front_image_id = None
        self._back_image_id = None
        self._rect_cache = {}

    def _order_quad_points(self, points):
        pts = points.reshape(4, 2).astype(np.float32)
        ordered = np.zeros((4, 2), dtype=np.float32)
        sums = pts.sum(axis=1)
        diffs = np.diff(pts, axis=1).reshape(4)
        ordered[0] = pts[np.argmin(sums)]
        ordered[2] = pts[np.argmax(sums)]
        ordered[1] = pts[np.argmin(diffs)]
        ordered[3] = pts[np.argmax(diffs)]
        return ordered

    def _quad_aspect_ratio(self, ordered):
        top_w = np.linalg.norm(ordered[1] - ordered[0])
        bottom_w = np.linalg.norm(ordered[2] - ordered[3])
        left_h = np.linalg.norm(ordered[3] - ordered[0])
        right_h = np.linalg.norm(ordered[2] - ordered[1])
        width = (top_w + bottom_w) / 2.0
        height = (left_h + right_h) / 2.0
        if width == 0 or height == 0:
            return 0.0
        ratio = width / height
        return ratio if ratio <= 1.0 else 1.0 / ratio

    def _card_contours(self, gray):
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 50, 150)
        contours, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        threshold_contours = []
        for src in (blurred, cv2.bitwise_not(blurred)):
            _, binary = cv2.threshold(src, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            kernel = np.ones((7, 7), np.uint8)
            closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
            found, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            threshold_contours.extend(found)

        return list(contours) + threshold_contours

    def _find_card_rect_details(self, image, frame_hint=None):
        """frame_hint = (fx, fy, fw, fh) normalized 0~1. 있으면 그 영역만 crop 후 detect.
        detect 실패 + frame_hint 있음 → frame_hint quad 자체를 카드로 가정 (fallback)."""
        if image is None or image.size == 0:
            return {
                "warped": None,
                "quad": None,
                "largest": None,
                "imperfect_quad": None,
                "ratio": 0.0,
                "area_ratio": 0.0,
            }

        cache_key = (id(image), frame_hint) if frame_hint is not None else id(image)
        cached = self._rect_cache.get(cache_key)
        if cached is not None:
            return cached

        if len(image.shape) == 2:
            color = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
            gray = image
        else:
            color = image
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)

        if frame_hint is not None:
            H, W = gray.shape
            fx, fy, fw, fh = frame_hint
            x0 = max(0, min(W - 1, int(fx * W)))
            y0 = max(0, min(H - 1, int(fy * H)))
            x1 = max(x0 + 1, min(W, int((fx + fw) * W)))
            y1 = max(y0 + 1, min(H, int((fy + fh) * H)))
            color = color[y0:y1, x0:x1]
            gray = gray[y0:y1, x0:x1]

        h, w = gray.shape
        image_area = float(h * w)
        contours = self._card_contours(gray)
        largest = None
        largest_area = 0.0
        imperfect_quad = None
        candidates = []

        for contour in contours:
            area = cv2.contourArea(contour)
            if area <= 0:
                continue
            if area > largest_area:
                largest_area = area
                largest = contour

            peri = cv2.arcLength(contour, True)
            approx = cv2.approxPolyDP(contour, 0.02 * peri, True)
            if len(approx) != 4 or area < image_area * 0.2:
                continue

            ordered = self._order_quad_points(approx)
            ratio = self._quad_aspect_ratio(ordered)
            if 0.6 <= ratio <= 0.85:
                candidates.append((area, ordered, ratio))
            elif imperfect_quad is None or area > imperfect_quad[0]:
                imperfect_quad = (area, ratio)

        if not candidates:
            if frame_hint is not None and gray.size > 0:
                ch, cw = gray.shape
                ordered = np.array([
                    [0, 0],
                    [cw - 1, 0],
                    [cw - 1, ch - 1],
                    [0, ch - 1],
                ], dtype=np.float32)
                dst = np.array([
                    [0, 0],
                    [self.CARD_WIDTH - 1, 0],
                    [self.CARD_WIDTH - 1, self.CARD_HEIGHT - 1],
                    [0, self.CARD_HEIGHT - 1],
                ], dtype=np.float32)
                matrix = cv2.getPerspectiveTransform(ordered, dst)
                warped = cv2.warpPerspective(color, matrix, (self.CARD_WIDTH, self.CARD_HEIGHT))
                ratio = cw / float(ch) if ch > 0 else 0.0
                if ratio > 1.0:
                    ratio = 1.0 / ratio
                details = {
                    "warped": warped,
                    "quad": ordered,
                    "largest": largest,
                    "imperfect_quad": None,
                    "ratio": ratio,
                    "area_ratio": 1.0,
                    "from_frame_hint": True,
                }
                self._rect_cache[cache_key] = details
                return details

            details = {
                "warped": None,
                "quad": None,
                "largest": largest,
                "imperfect_quad": imperfect_quad,
                "ratio": 0.0,
                "area_ratio": largest_area / image_area if image_area else 0.0,
            }
            self._rect_cache[cache_key] = details
            return details

        area, ordered, ratio = max(candidates, key=lambda item: item[0])
        dst = np.array([
            [0, 0],
            [self.CARD_WIDTH - 1, 0],
            [self.CARD_WIDTH - 1, self.CARD_HEIGHT - 1],
            [0, self.CARD_HEIGHT - 1],
        ], dtype=np.float32)
        matrix = cv2.getPerspectiveTransform(ordered, dst)
        warped = cv2.warpPerspective(color, matrix, (self.CARD_WIDTH, self.CARD_HEIGHT))
        details = {
            "warped": warped,
            "quad": ordered,
            "largest": largest,
            "imperfect_quad": None,
            "ratio": ratio,
            "area_ratio": area / image_area if image_area else 0.0,
        }
        self._rect_cache[cache_key] = details
        return details

    def _find_card_rect(self, image, frame_hint=None):
        details = self._find_card_rect_details(image, frame_hint=frame_hint)
        return details["warped"]

    def _cached_warped_card(self, image):
        if id(image) == self._front_image_id and self._warped_front is not None:
            return self._warped_front
        if id(image) == self._back_image_id and self._warped_back is not None:
            return self._warped_back
        return self._find_card_rect(image)

    def detect_card_confidence(self, image, frame_hint=None) -> dict:
        details = self._find_card_rect_details(image, frame_hint=frame_hint)
        if details["warped"] is not None:
            ratio_dev = abs(details["ratio"] - self.CARD_RATIO)
            if ratio_dev <= 0.05 and details["area_ratio"] >= 0.2:
                confidence = min(1.0, 0.95 - ratio_dev)
                reason = "Quadrilateral card detected with correct aspect ratio"
            else:
                confidence = max(0.6, min(0.8, 0.8 - ratio_dev * 0.5))
                reason = "Quadrilateral card detected with imperfect aspect ratio"
            return {"detected": True, "confidence": round(float(confidence), 2), "reason": reason}

        imperfect_quad = details["imperfect_quad"]
        if imperfect_quad is not None:
            _, ratio = imperfect_quad
            ratio_dev = min(abs(ratio - 0.6), abs(ratio - 0.85))
            confidence = max(0.6, min(0.8, 0.75 - ratio_dev * 0.5))
            reason = "Quadrilateral card candidate detected with imperfect aspect ratio"
            return {"detected": True, "confidence": round(float(confidence), 2), "reason": reason}

        largest = details["largest"]
        area_ratio = details["area_ratio"]
        if largest is not None and area_ratio > 0:
            confidence = max(0.3, min(0.5, area_ratio))
            reason = "No valid quadrilateral; largest contour used for low-confidence detection"
            return {"detected": False, "confidence": round(float(confidence), 2), "reason": reason}

        return {"detected": False, "confidence": 0.0, "reason": "No card-like contour detected"}

    def _card_image_or_roi(self, image):
        warped = self._cached_warped_card(image)
        if warped is not None:
            return warped
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        x, y, w, h = self._find_card_in_image(gray)
        return image[y:y + h, x:x + w]

    def _find_card_in_image(self, gray):
        """사진에서 카드 영역(bounding rect)을 찾아 반환. 실패시 전체 이미지 반환."""
        warped = self._find_card_rect(cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR))
        if warped is not None:
            h, w = warped.shape[:2]
            return 0, 0, w, h

        h, w = gray.shape
        blurred = cv2.GaussianBlur(gray, (15, 15), 0)

        def _try_detect(img_to_thresh):
            _, binary = cv2.threshold(img_to_thresh, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
            kernel = np.ones((15, 15), np.uint8)
            closed = cv2.morphologyEx(binary, cv2.MORPH_CLOSE, kernel)
            contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
            if not contours:
                return None
            largest = max(contours, key=cv2.contourArea)
            x, y, cw, ch = cv2.boundingRect(largest)
            if cw * ch < w * h * 0.3:
                return None
            return x, y, cw, ch

        # 정방향 시도 → 실패시 반전 이미지로 재시도 (검정 배경 대응)
        result = _try_detect(blurred) or _try_detect(cv2.bitwise_not(blurred))
        if result is None:
            return 0, 0, w, h
        x, y, cw, ch = result
        pad = 5
        x = max(0, x - pad)
        y = max(0, y - pad)
        cw = min(w - x, cw + 2 * pad)
        ch = min(h - y, ch + 2 * pad)
        return x, y, cw, ch

    def _detect_inner_border_margins(self, card_gray) -> tuple[int, int, int, int]:
        rh, rw = card_gray.shape
        blurred = cv2.GaussianBlur(card_gray, (5, 5), 0)
        edges = cv2.Canny(blurred, 40, 120)

        min_len = max(20, int(min(rh, rw) * 0.25))
        max_gap = max(5, int(min(rh, rw) * 0.03))
        lines = cv2.HoughLinesP(
            edges,
            rho=1,
            theta=np.pi / 180,
            threshold=max(20, int(min(rh, rw) * 0.08)),
            minLineLength=min_len,
            maxLineGap=max_gap,
        )

        outer_frac = 0.18
        h_band = max(2, int(rh * outer_frac))
        w_band = max(2, int(rw * outer_frac))
        min_offset = max(2, int(min(rh, rw) * 0.015))
        top_candidates = []
        bottom_candidates = []
        left_candidates = []
        right_candidates = []

        if lines is not None:
            for line in lines[:, 0, :]:
                x1, y1, x2, y2 = map(int, line)
                dx = abs(x2 - x1)
                dy = abs(y2 - y1)
                if dx >= dy * 3:
                    y = (y1 + y2) / 2.0
                    if min_offset <= y <= h_band:
                        top_candidates.append(y)
                    elif rh - h_band <= y <= rh - 1 - min_offset:
                        bottom_candidates.append(y)
                elif dy >= dx * 3:
                    x = (x1 + x2) / 2.0
                    if min_offset <= x <= w_band:
                        left_candidates.append(x)
                    elif rw - w_band <= x <= rw - 1 - min_offset:
                        right_candidates.append(x)

        fallback_top = fallback_bottom = max(1, int(rh * 0.08))
        fallback_left = fallback_right = max(1, int(rw * 0.08))

        top_m = int(round(np.median(top_candidates))) if top_candidates else fallback_top
        bottom_line = int(round(np.median(bottom_candidates))) if bottom_candidates else rh - 1 - fallback_bottom
        left_m = int(round(np.median(left_candidates))) if left_candidates else fallback_left
        right_line = int(round(np.median(right_candidates))) if right_candidates else rw - 1 - fallback_right

        bottom_m = max(0, rh - 1 - bottom_line)
        right_m = max(0, rw - 1 - right_line)
        return max(0, top_m), bottom_m, max(0, left_m), right_m

    def analyze_centering(self, image) -> tuple[float, str, str]:
        card = self._card_image_or_roi(image)
        card_gray = cv2.cvtColor(card, cv2.COLOR_BGR2GRAY)
        top_m, bottom_m, left_m, right_m = self._detect_inner_border_margins(card_gray)

        def compute_score(m1, m2):
            total = m1 + m2
            if total == 0:
                return 8.0, 50.0, 50.0
            ratio = m1 / total
            dev = abs(ratio - 0.5)
            # 실제 PSA 기준: 센터링 최악(80:20)도 PSA 6~7 수준 → 최솟값 5.0, 감도 완화
            score = max(5.0, 10.0 - (dev / 0.05) * 0.8)
            return score, round(ratio * 100), round((1 - ratio) * 100)

        lr_score, lp, rp = compute_score(left_m, right_m)
        tb_score, tp, bp = compute_score(top_m, bottom_m)
        score = round(min(10.0, (lr_score + tb_score) / 2), 1)
        ratio = f"좌:우 = {int(lp)}:{int(rp)}, 상:하 = {int(tp)}:{int(bp)}"

        lr_dev = abs(lp - 50)
        tb_dev = abs(tp - 50)
        if score >= 9.5:
            detail = f"인쇄 여백 균일 — 감점 없음 ({ratio})"
        elif score >= 8.0:
            detail = f"경미한 센터링 불균형 감지 ({ratio})"
        elif lr_dev >= tb_dev:
            detail = f"좌우 센터링 불균형 감지 — 주요 감점 요인 ({ratio})"
        else:
            detail = f"상하 센터링 불균형 감지 — 주요 감점 요인 ({ratio})"

        return score, detail, ratio

    def analyze_corner(self, image) -> float:
        h, w = image.shape[:2]
        tip_h = max(1, int(h * 0.2))
        tip_w = max(1, int(w * 0.2))
        tip = image[:tip_h, :tip_w]
        if tip.size == 0:
            tip = image

        hsv = cv2.cvtColor(tip, cv2.COLOR_BGR2HSV)
        white_mask = cv2.inRange(
            hsv,
            np.array([0, 0, 200]),
            np.array([180, 15, 255]),
        )
        whitening_ratio = np.count_nonzero(white_mask) / white_mask.size

        gray_tip = cv2.cvtColor(tip, cv2.COLOR_BGR2GRAY)
        lap_var = float(cv2.Laplacian(gray_tip, cv2.CV_64F).var()) if gray_tip.size else 0.0
        blur_penalty = max(0.0, (80.0 - lap_var) / 80.0) * 2.0
        whitening_penalty = min(6.0, whitening_ratio * 30.0)
        score = max(1.0, min(10.0, 10.0 - whitening_penalty - blur_penalty))
        return round(score, 1)

    def crop_corners(self, image) -> list:
        card = self._cached_warped_card(image)
        if card is None:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
            x, y, w, h = self._find_card_in_image(gray)
            card = image[y:y + h, x:x + w]
        if card.size == 0:
            card = image

        h, w = card.shape[:2]
        crop_h = max(1, int(h * 0.2))
        crop_w = max(1, int(w * 0.2))
        tl = card[:crop_h, :crop_w]
        tr = cv2.flip(card[:crop_h, w - crop_w:w], 1)
        bl = cv2.flip(card[h - crop_h:h, :crop_w], 0)
        br = cv2.flip(card[h - crop_h:h, w - crop_w:w], -1)
        return [tl, tr, bl, br]

    def analyze_surface(self, image) -> tuple[float, float]:
        card = self._card_image_or_roi(image)
        card_gray = cv2.cvtColor(card, cv2.COLOR_BGR2GRAY)
        rh, rw = card_gray.shape

        bfrac = 0.05
        bh = max(2, int(rh * bfrac))
        bw = max(2, int(rw * bfrac))

        lap = cv2.Laplacian(card_gray, cv2.CV_64F)
        border_lap = np.concatenate([
            lap[:bh, :].flatten(),
            lap[-bh:, :].flatten(),
            lap[bh:-bh, :bw].flatten(),
            lap[bh:-bh, -bw:].flatten(),
        ])

        if border_lap.size == 0:
            return 7.0, 7.0

        lap_std = float(np.std(border_lap))
        score = max(4.0, min(10.0, 10.0 - max(0.0, lap_std - 5.0) * 0.30))
        return round(score, 1), lap_std

    def analyze_whitening(self, image) -> tuple[float, bool, float]:
        card = self._card_image_or_roi(image)

        hsv = cv2.cvtColor(card, cv2.COLOR_BGR2HSV)
        h, w = hsv.shape[:2]
        margin = max(int(min(h, w) * 0.04), 4)
        regions = [
            hsv[:margin, margin:w - margin],
            hsv[-margin:, margin:w - margin],
            hsv[margin:h - margin, :margin],
            hsv[margin:h - margin, w - margin:],
        ]
        total, white = 0, 0
        for region in regions:
            if region.size == 0:
                continue
            total += region.shape[0] * region.shape[1]
            mask = cv2.inRange(region,
                               np.array([0, 0, 210]),
                               np.array([180, 10, 255]))
            white += int(mask.sum() / 255)
        ratio = white / total if total > 0 else 0.0
        score = max(1.0, 10.0 - ratio * 100)
        heavy = ratio > 0.05
        return round(min(10.0, score), 1), heavy, ratio

    _CORNER_NAMES = ['앞 좌상단', '앞 우상단', '앞 좌하단', '앞 우하단',
                     '뒤 좌상단', '뒤 우상단', '뒤 좌하단', '뒤 우하단']

    @classmethod
    def calculate_grade(cls, weighted_raw: float, metrics: dict, has_major: bool):
        """spec § 3 — 9단계 cap (weakest link rule).
        weighted AND min(metrics) 둘 다 충족해야 등급 부여.
        S+/S 는 major defect 시 강등."""
        min_metric = min(metrics.values()) if metrics else 0.0
        for grade, w_thr, m_thr, color in cls._GRADE_TABLE:
            if weighted_raw < w_thr or min_metric < m_thr:
                continue
            if grade in ("S+", "S") and has_major:
                continue
            return grade, color
        return cls._DEFAULT_GRADE

    @staticmethod
    def has_major_defect(metrics: dict, reasons: List[DeductionReason]) -> bool:
        """spec § 3 — major defect 자동 trigger.
        조건: 메트릭 한 항목 < 4.0 OR major whitening 2+ OR major reason 2+."""
        if any(m < 4.0 for m in metrics.values()):
            return True
        major_whitening = [r for r in reasons if r.type == "whitening" and r.severity == "major"]
        if len(major_whitening) > 1:
            return True
        major_total = [r for r in reasons if r.severity == "major"]
        if len(major_total) > 1:
            return True
        return False

    def detect_whitening_regions(self, card_roi) -> list:
        """spec § 2 — HSV S 부스트 → 흰 영역 highlight → bbox list."""
        if card_roi is None or card_roi.size == 0:
            return []
        hsv = cv2.cvtColor(card_roi, cv2.COLOR_BGR2HSV).astype(np.float32)
        hsv[:, :, 1] = np.clip(hsv[:, :, 1] * 2.0, 0, 255)
        boosted = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)
        diff = cv2.absdiff(boosted, card_roi)
        mask = (diff.sum(axis=2) > 60).astype(np.uint8) * 255
        h, w = mask.shape
        total_pixels = float(h * w)
        min_area = max(20, int(total_pixels * 0.0005))
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        regions = []
        for c in contours:
            area = float(cv2.contourArea(c))
            if area < min_area:
                continue
            x, y, cw, ch = cv2.boundingRect(c)
            area_ratio = area / total_pixels
            confidence = min(1.0, area_ratio * 100.0)
            regions.append({
                "bbox": (x / w, y / h, cw / w, ch / h),
                "confidence": float(round(confidence, 2)),
                "area_ratio": float(round(area_ratio, 4)),
            })
        return regions

    def detect_scratch_regions(self, card_roi) -> list:
        """spec § 2 — CLAHE local contrast → 선형(스크래치) / 점형(찍힘) 패턴."""
        if card_roi is None or card_roi.size == 0:
            return []
        lab = cv2.cvtColor(card_roi, cv2.COLOR_BGR2LAB)
        l_channel = lab[:, :, 0]
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(l_channel)
        diff = cv2.absdiff(enhanced, l_channel)
        mask = (diff > 40).astype(np.uint8) * 255
        h, w = mask.shape
        total_pixels = float(h * w)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        regions = []
        for c in contours:
            x, y, cw, ch = cv2.boundingRect(c)
            if cw < 4 or ch < 4:
                continue
            aspect = max(cw / max(ch, 1), ch / max(cw, 1))
            area = float(cv2.contourArea(c))
            if aspect > 4.0 and area > 50:
                rtype = "scratch"
            elif 1.0 <= aspect <= 4.0 and 30 <= area < 200:
                rtype = "dent"
            else:
                continue
            confidence = min(1.0, area / (total_pixels * 0.005))
            regions.append({
                "bbox": (x / w, y / h, cw / w, ch / h),
                "type": rtype,
                "confidence": float(round(confidence, 2)),
            })
        return regions

    def _check_lighting_quality(self, card_roi) -> dict:
        """ROI 기반 lighting 5종 검사. 사용자 design = AI 그레이딩 품질 절반.
        under_exposed / over_exposed / glare / blur / uneven (shadow)."""
        if card_roi is None or card_roi.size == 0:
            return {"quality": "good", "issues": []}

        issues = []
        hsv = cv2.cvtColor(card_roi, cv2.COLOR_BGR2HSV)
        v = hsv[:, :, 2]
        v_mean = float(v.mean())
        v_std = float(v.std())
        total = float(v.size)

        if v_mean < 60:
            issues.append({
                "type": "under_exposed",
                "severity": "bad",
                "reason": "촬영 환경이 너무 어두워요. 밝은 곳에서 다시 촬영해 주세요",
            })

        overexp_ratio = float((v > 250).sum()) / total
        if overexp_ratio > 0.15:
            issues.append({
                "type": "over_exposed",
                "severity": "bad" if overexp_ratio > 0.30 else "warning",
                "reason": "사진이 너무 밝아 카드가 잘 안 보여요. 직사광선/플래시를 피해 다시 촬영해 주세요",
            })

        bright_mask = (v > 245).astype(np.uint8) * 255
        contours, _ = cv2.findContours(
            bright_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        glare_area_ratio = (max([cv2.contourArea(c) for c in contours]) / total
                            if contours else 0.0)
        if glare_area_ratio > 0.05:
            issues.append({
                "type": "glare",
                "severity": "bad" if glare_area_ratio > 0.12 else "warning",
                "reason": "카드 표면에 빛 반사가 강해요. 각도를 바꿔 다시 촬영해 주세요",
            })

        gray = cv2.cvtColor(card_roi, cv2.COLOR_BGR2GRAY)
        lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        if lap_var < 50:
            issues.append({
                "type": "blur",
                "severity": "bad" if lap_var < 30 else "warning",
                "reason": "사진이 흐리게 촬영됐어요. 카드를 고정한 뒤 다시 촬영해 주세요",
            })

        if v_std > 70:
            issues.append({
                "type": "uneven_lighting",
                "severity": "warning",
                "reason": "조명이 균일하지 않아요. 그림자 없는 곳에서 촬영하면 정확도가 더 좋아져요",
            })

        if any(i["severity"] == "bad" for i in issues):
            quality = "bad"
        elif any(i["severity"] == "warning" for i in issues):
            quality = "warning"
        else:
            quality = "good"
        return {"quality": quality, "issues": issues}

    def detect_corner_damage(self, card_roi) -> list:
        """spec § 2 — 4 코너 자동 추출 + 코너별 score 산출."""
        if card_roi is None or card_roi.size == 0:
            return []
        h, w = card_roi.shape[:2]
        corner_h = max(10, int(h * 0.15))
        corner_w = max(10, int(w * 0.15))
        corners_map = {
            "top_left":     (0,            0,            corner_w, corner_h),
            "top_right":    (w - corner_w, 0,            corner_w, corner_h),
            "bottom_left":  (0,            h - corner_h, corner_w, corner_h),
            "bottom_right": (w - corner_w, h - corner_h, corner_w, corner_h),
        }
        results = []
        for position, (x, y, cw, ch) in corners_map.items():
            roi = card_roi[y:y + ch, x:x + cw]
            if roi.size == 0:
                continue
            score = self.analyze_corner(roi)
            if score >= 9.0:
                continue
            severity = "major" if score < 6.0 else ("moderate" if score < 8.0 else "minor")
            results.append({
                "position": position,
                "bbox": (x / w, y / h, cw / w, ch / h),
                "score": float(score),
                "severity": severity,
                "confidence": float(round(min(1.0, (9.0 - score) / 5.0), 2)),
            })
        return results

    def analyze(self, front, back, corners: list | None = None,
                frame_hint: tuple | None = None) -> AnalysisResult:
        """frame_hint = (fx, fy, fw, fh) normalized 0~1.
        Flutter capture screen 의 frame overlay 좌표 → backend 분석 ROI 기준."""
        self._rect_cache = {}
        self._front_image_id = id(front)
        self._back_image_id = id(back)
        self._warped_front = self._find_card_rect(front, frame_hint=frame_hint)
        self._warped_back = self._find_card_rect(back, frame_hint=frame_hint)
        detection = self.detect_card_confidence(front, frame_hint=frame_hint)

        centering, centering_detail, centering_ratio = self.analyze_centering(front)
        if corners is None:
            corners = self.crop_corners(front) + self.crop_corners(back)

        if corners:
            corner_scores = [self.analyze_corner(c) for c in corners]
            corner_avg = round(sum(corner_scores) / len(corner_scores), 1)
            min_cs = min(corner_scores)
            min_idx = corner_scores.index(min_cs)
            if min_cs >= 9.0:
                corner_detail = f"8개 코너 모두 양호 (평균 {corner_avg}점)"
            else:
                corner_detail = f"최저 {min_cs}점 ({self._CORNER_NAMES[min_idx]}) — 마모 감지"
        else:
            corner_scores = []
            corner_avg = 9.0
            min_cs = 9.0
            corner_detail = "코너 입력 없음 — 기본값 9.0"

        surface_front, std_front = self.analyze_surface(front)
        surface_back, std_back = self.analyze_surface(back)
        surface_avg = round((surface_front + surface_back) / 2, 1)

        def _surface_label(score):
            if score >= 9.0:
                return "깨끗함"
            elif score >= 7.0:
                return "경미한 스크래치"
            else:
                return "스크래치/오염 감지"

        surface_detail = (
            f"앞면 {surface_front}점({_surface_label(surface_front)}) / "
            f"뒷면 {surface_back}점({_surface_label(surface_back)})"
        )

        whitening_score, heavy, ratio = self.analyze_whitening(back)
        back_corner_whitening = [self.analyze_whitening(c)[0] for c in corners[4:]]
        whitening_combined = round((whitening_score + sum(back_corner_whitening) / 4) / 2, 1)
        _, heavy, ratio = self.analyze_whitening(back)

        ratio_pct = ratio * 100
        if ratio_pct < 0.5:
            whitening_detail = f"백화 거의 없음 ({ratio_pct:.2f}%)"
        elif ratio_pct < 2.0:
            whitening_detail = f"경미한 백화 ({ratio_pct:.1f}%) — 테두리 일부 감지"
        elif heavy:
            whitening_detail = f"심한 백화 ({ratio_pct:.1f}%) — 총점 15% 추가 감점"
        else:
            whitening_detail = f"백화 {ratio_pct:.1f}% 감지"

        weighted = (
            centering * 0.15 +
            corner_avg * 0.35 +
            surface_avg * 0.25 +
            whitening_combined * 0.25
        )
        if heavy:
            weighted *= 0.85

        # 최저 항목 캡: 코너·표면·화이트닝 중 최솟값 기준 (센터링 제외 — 측정 오차 큼)
        quality_lowest = min(corner_avg, surface_avg, whitening_combined)
        final = min(weighted, quality_lowest + 2.0)

        # 센터링 캡: 뚜렷한 불균형일 때만 살짝 제한 (PSA에서 센터링 단독으로 큰 감점 없음)
        if centering < 6.0:
            final = min(final, 9.0)
        if centering < 5.5:
            final = min(final, 8.5)

        # 표면·화이트닝·코너 심각 결함 캡 (PSA 주요 감점 요인)
        if surface_avg < 6.0:
            final = min(final, 7.0)
        if whitening_combined < 5.0:
            final = min(final, 7.0)
        elif whitening_combined < 7.0:
            final = min(final, 8.5)
        if corner_avg < 7.0:
            final = min(final, 8.0)

        total = round(min(10.0, max(1.0, final)), 1)

        # === Day 1 신규 — 자체 9단계 등급 + 결함 reason / region ===
        edge_score = round((corner_avg + surface_avg) / 2, 1)
        edge_detail = f"코너+표면 종합 ({edge_score}점)"

        metrics_dict = {
            "centering": centering,
            "corner":    corner_avg,
            "surface":   surface_avg,
            "whitening": whitening_combined,
            "edge":      edge_score,
        }
        w = self._WEIGHTS
        weighted_raw = (
            centering * w["centering"]
            + corner_avg * w["corner"]
            + surface_avg * w["surface"]
            + whitening_combined * w["whitening"]
            + edge_score * w["edge"]
        )
        if heavy:
            weighted_raw *= 0.85
        weighted_raw = round(min(10.0, max(0.0, weighted_raw)), 2)

        deduction_reasons: List[DeductionReason] = []
        defect_regions: List[DefectRegion] = []
        next_id = {"n": 0}

        def add_reason(rtype, side, position, severity, confidence, penalty,
                       bbox, label, explanation, color, region_type=None):
            next_id["n"] += 1
            deduction_reasons.append(DeductionReason(
                id=str(next_id["n"]),
                type=rtype, side=side, position=position,
                severity=severity, confidence=confidence, penalty=penalty,
                bbox=bbox, label=label, explanation=explanation,
            ))
            if bbox is not None:
                defect_regions.append(DefectRegion(
                    type=region_type or rtype, bbox=bbox, side=side, color=color,
                ))

        if centering < 9.0:
            sev = "major" if centering < 5.0 else ("moderate" if centering < 7.0 else "minor")
            add_reason(
                "centering", "front", "center", sev,
                0.9, round(10.0 - centering, 1), None,
                f"센터링 편차 — {centering_ratio}",
                f"좌우/상하 여백 비율: {centering_ratio}",
                "#F39C12",
            )

        warped_front = self._cached_warped_card(front)
        warped_back = self._cached_warped_card(back)

        for side_name, side_warped in (("front", warped_front), ("back", warped_back)):
            for c in self.detect_corner_damage(side_warped):
                add_reason(
                    "corner", side_name, c["position"], c["severity"],
                    c["confidence"], round(10.0 - c["score"], 1), c["bbox"],
                    f"{side_name} {c['position']} 코너 마모 후보",
                    f"코너 영역 분석 점수 {c['score']:.1f}/10",
                    "#E67E22",
                    region_type="corner_damage",
                )

        for w_region in self.detect_whitening_regions(warped_back):
            ar = w_region["area_ratio"]
            sev = "major" if ar > 0.02 else ("moderate" if ar > 0.005 else "minor")
            add_reason(
                "whitening", "back", "", sev,
                w_region["confidence"], round(min(2.0, ar * 100.0), 1),
                w_region["bbox"], "백화 후보 영역",
                f"채도 부스트 분석 검출 — 영역 비율 {ar * 100:.2f}%",
                "#3498DB",
            )

        for side_name, side_warped in (("front", warped_front), ("back", warped_back)):
            for s_region in self.detect_scratch_regions(side_warped):
                conf = s_region["confidence"]
                sev = "moderate" if conf > 0.6 else "minor"
                is_scratch = s_region["type"] == "scratch"
                label = "스크래치 후보" if is_scratch else "찍힘 후보"
                add_reason(
                    s_region["type"], side_name, "", sev,
                    conf, 0.5 if is_scratch else 0.3,
                    s_region["bbox"], label,
                    f"CLAHE local contrast 분석 — {label}",
                    "#9B59B6",
                )

        has_major = self.has_major_defect(metrics_dict, deduction_reasons)
        grade, grade_color = self.calculate_grade(weighted_raw, metrics_dict, has_major)
        total_score_display = round(weighted_raw, 1)

        # === Retake / capture quality (사용자 design: 틀=가이드, 분석=ROI, retake=분석 불가능 시) ===
        det_conf = detection["confidence"]
        retake_reasons_text = []
        if warped_front is None:
            retake_reasons_text.append("앞면 카드 외곽을 감지하지 못했어요")
        if warped_back is None:
            retake_reasons_text.append("뒷면 카드 외곽을 감지하지 못했어요")
        if det_conf < 0.40:
            retake_reasons_text.append(f"촬영 품질이 낮습니다 (신뢰도 {det_conf:.2f})")

        # === Lighting quality 5종 (사용자 design: AI 그레이딩 품질 절반) ===
        lighting_front = self._check_lighting_quality(warped_front) if warped_front is not None else {"quality": "good", "issues": []}
        lighting_back = self._check_lighting_quality(warped_back) if warped_back is not None else {"quality": "good", "issues": []}
        for li in lighting_front["issues"] + lighting_back["issues"]:
            if li["severity"] == "bad":
                retake_reasons_text.append(li["reason"])

        lighting_quality = "good"
        for li in lighting_front["issues"] + lighting_back["issues"]:
            if li["severity"] == "bad":
                lighting_quality = "bad"
                break
            if li["severity"] == "warning":
                lighting_quality = "warning"

        retake_required = len(retake_reasons_text) > 0
        if retake_required:
            capture_quality = "bad"
        elif det_conf < 0.55 or lighting_quality == "warning":
            capture_quality = "warning"
        else:
            capture_quality = "good"
        retake_reason = " / ".join(retake_reasons_text)

        return AnalysisResult(
            centering_score=centering,
            centering_ratio=centering_ratio,
            detection_confidence=detection["confidence"],
            corner_score=corner_avg,
            surface_score=surface_avg,
            whitening_score=whitening_combined,
            edge_score=edge_score,
            total_score=total_score_display,
            heavy_whitening=heavy,
            centering_detail=centering_detail,
            corner_detail=corner_detail,
            surface_detail=surface_detail,
            whitening_detail=whitening_detail,
            edge_detail=edge_detail,
            weighted_score=weighted_raw,
            total_score_display=total_score_display,
            grade=grade,
            grade_color=grade_color,
            deduction_reasons=deduction_reasons,
            defect_regions=defect_regions,
            has_major_defect=has_major,
            retake_required=retake_required,
            retake_reason=retake_reason,
            capture_quality=capture_quality,
            screen_suspected=False,
            screen_suspect_reason="",
        )
