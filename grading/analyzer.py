import json
import os
import uuid
from datetime import datetime
from typing import List, Optional

import cv2
import numpy as np
from models import AnalysisResult, DeductionReason, DefectRegion

DEBUG_ROOT = "/tmp/grading_debug"


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

    # ── Debug output helpers (Phase 2-A) ─────────────────────────────────
    @staticmethod
    def _new_session_id() -> str:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        return f"{ts}_{uuid.uuid4().hex[:8]}"

    @staticmethod
    def _debug_dir(session_id: str) -> str:
        d = os.path.join(DEBUG_ROOT, session_id)
        os.makedirs(d, exist_ok=True)
        return d

    @staticmethod
    def _debug_save_image(session_id: str, filename: str, image) -> Optional[str]:
        if image is None or image.size == 0:
            return None
        path = os.path.join(GradingAnalyzer._debug_dir(session_id), filename)
        try:
            cv2.imwrite(path, image)
            return path
        except Exception:
            return None

    @staticmethod
    def _build_clahe_visual(card_roi):
        """detect_scratch_regions 의 CLAHE local contrast 결과를 시각용 image 로 변환."""
        if card_roi is None or card_roi.size == 0:
            return None
        lab = cv2.cvtColor(card_roi, cv2.COLOR_BGR2LAB)
        l_channel = lab[:, :, 0]
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(l_channel)
        diff = cv2.absdiff(enhanced, l_channel)
        diff_norm = cv2.normalize(diff, None, 0, 255, cv2.NORM_MINMAX)
        return cv2.cvtColor(diff_norm.astype(np.uint8), cv2.COLOR_GRAY2BGR)

    @staticmethod
    def _build_whitening_mask_visual(card_roi):
        """detect_whitening_regions 의 mask 시각용.
        P0-C hotfix issue 4: 카드 전체 빨강 마스크 X → 테두리 band 10% 만.
        + min/max area filter (작은 후보만, 큰 반사광 제외)."""
        if card_roi is None or card_roi.size == 0:
            return None
        h, w = card_roi.shape[:2]
        if h < 20 or w < 20:
            return card_roi.copy()
        hsv = cv2.cvtColor(card_roi, cv2.COLOR_BGR2HSV).astype(np.float32)
        hsv[:, :, 1] = np.clip(hsv[:, :, 1] * 2.0, 0, 255)
        boosted = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)
        diff = cv2.absdiff(boosted, card_roi)
        mask = (diff.sum(axis=2) > 75).astype(np.uint8) * 255

        # P0-C hotfix: band mask only (외쪽 10%)
        band = max(8, int(min(h, w) * 0.10))
        band_mask = np.zeros((h, w), dtype=np.uint8)
        band_mask[:band, :] = 255
        band_mask[-band:, :] = 255
        band_mask[:, :band] = 255
        band_mask[:, -band:] = 255
        mask = cv2.bitwise_and(mask, band_mask)

        # min/max area filter
        total = h * w
        min_area = max(15, int(total * 0.00005))
        max_area = int(total * 0.003)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        filtered_mask = np.zeros_like(mask)
        for c in contours:
            area = cv2.contourArea(c)
            if min_area <= area <= max_area:
                cv2.drawContours(filtered_mask, [c], -1, 255, -1)

        # 후보 영역만 작은 outline + 노란 박스 (큰 빨강 마스크 X)
        overlay = card_roi.copy()
        contours2, _ = cv2.findContours(filtered_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        for c in contours2:
            x, y, cw, ch = cv2.boundingRect(c)
            # 작은 박스 outline (노란색 = 시각 강조, 카드 그림 위에 살짝)
            cv2.rectangle(overlay, (x - 2, y - 2), (x + cw + 2, y + ch + 2),
                          (0, 255, 255), 2)  # BGR 노란색
        return overlay

    def _write_debug_json(self, session_id: str, payload: dict) -> Optional[str]:
        path = os.path.join(self._debug_dir(session_id), "analysis_debug.json")
        try:
            with open(path, "w", encoding="utf-8") as f:
                json.dump(payload, f, ensure_ascii=False, indent=2, default=str)
            return path
        except Exception:
            return None
    # ─────────────────────────────────────────────────────────────────────

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
            # Codex 진단: frame_hint quad 전체를 카드로 가정하는 fallback = 위험 (배경/손 포함).
            # quality gate — frame_hint 의 aspect 가 카드 비율 (0.62~0.82) 통과 시만 fallback 허용.
            if frame_hint is not None and gray.size > 0:
                ch, cw = gray.shape
                hint_ratio = cw / float(ch) if ch > 0 else 0.0
                if hint_ratio > 1.0:
                    hint_ratio = 1.0 / hint_ratio
                if 0.62 <= hint_ratio <= 0.82:
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
                    details = {
                        "warped": warped,
                        "quad": ordered,
                        "largest": largest,
                        "imperfect_quad": None,
                        "ratio": hint_ratio,
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

    def _detect_inner_border_margins(self, card_gray) -> dict:
        """P0-1: dict 반환 — margins + line 좌표 + candidate 수 + fallback flag.
        호출자가 confidence/source 산출에 사용."""
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

        top_fb = not top_candidates
        bot_fb = not bottom_candidates
        left_fb = not left_candidates
        right_fb = not right_candidates

        top_m = int(round(np.median(top_candidates))) if top_candidates else fallback_top
        bottom_line = int(round(np.median(bottom_candidates))) if bottom_candidates else rh - 1 - fallback_bottom
        left_m = int(round(np.median(left_candidates))) if left_candidates else fallback_left
        right_line = int(round(np.median(right_candidates))) if right_candidates else rw - 1 - fallback_right

        bottom_m = max(0, rh - 1 - bottom_line)
        right_m = max(0, rw - 1 - right_line)
        return {
            "top_m": max(0, top_m),
            "bottom_m": bottom_m,
            "left_m": max(0, left_m),
            "right_m": right_m,
            "top_y_norm": float(top_m / rh) if rh > 0 else 0.0,
            "bottom_y_norm": float(bottom_line / rh) if rh > 0 else 1.0,
            "left_x_norm": float(left_m / rw) if rw > 0 else 0.0,
            "right_x_norm": float(right_line / rw) if rw > 0 else 1.0,
            "top_n": len(top_candidates),
            "bottom_n": len(bottom_candidates),
            "left_n": len(left_candidates),
            "right_n": len(right_candidates),
            "fallbacks_used": int(top_fb) + int(bot_fb) + int(left_fb) + int(right_fb),
        }

    @staticmethod
    def _compute_card_bbox(image, frame_hint, details):
        """P0-1: 사진 전체 normalized 0~1 card bbox (quad 외접 사각형).
        P0-fix-1: source 명시 — "detected" / "frame_hint_fallback".
        UI 가 source != "detected" 면 overlay 표시 안 함 (잘못된 박스 방지)."""
        if image is None or image.size == 0:
            return None
        H, W = image.shape[:2]
        if W <= 0 or H <= 0:
            return None
        quad = details.get("quad") if details else None
        from_hint = bool(details.get("from_frame_hint", False)) if details else False
        if quad is None:
            if frame_hint is not None:
                fx, fy, fw, fh = frame_hint
                return {
                    "x": float(fx), "y": float(fy),
                    "w": float(fw), "h": float(fh),
                    "source": "frame_hint_fallback",
                }
            return None
        if frame_hint is not None:
            fx, fy, fw, fh = frame_hint
            x_offset = fx * W
            y_offset = fy * H
            xs = quad[:, 0] + x_offset
            ys = quad[:, 1] + y_offset
        else:
            xs = quad[:, 0]
            ys = quad[:, 1]
        x_min, x_max = float(np.min(xs)), float(np.max(xs))
        y_min, y_max = float(np.min(ys)), float(np.max(ys))
        # from_hint = True → quad 가 frame_hint 자체 (실제 카드 외곽 아님)
        source = "frame_hint_fallback" if from_hint else "detected"
        return {
            "x": max(0.0, min(1.0, x_min / W)),
            "y": max(0.0, min(1.0, y_min / H)),
            "w": max(0.0, min(1.0, (x_max - x_min) / W)),
            "h": max(0.0, min(1.0, (y_max - y_min) / H)),
            "source": source,
        }

    @staticmethod
    def _compute_corner_regions(card_bbox):
        """P0-1: 4 corner bbox (사진 normalized 0~1, card_bbox 의 20% × 20%)."""
        if card_bbox is None:
            return None
        cx, cy = card_bbox["x"], card_bbox["y"]
        cw, ch = card_bbox["w"], card_bbox["h"]
        cw20, ch20 = cw * 0.2, ch * 0.2
        return {
            "top_left":     {"x": cx,             "y": cy,             "w": cw20, "h": ch20},
            "top_right":    {"x": cx + cw - cw20, "y": cy,             "w": cw20, "h": ch20},
            "bottom_left":  {"x": cx,             "y": cy + ch - ch20, "w": cw20, "h": ch20},
            "bottom_right": {"x": cx + cw - cw20, "y": cy + ch - ch20, "w": cw20, "h": ch20},
        }

    @staticmethod
    def _centering_confidence_source(d: dict, lr_pct: float, tb_pct: float) -> tuple[float, str]:
        """P0-1: candidate 수 + 대칭 evidence + fallback 기반 confidence/source 산출."""
        n_min = min(d["top_n"], d["bottom_n"], d["left_n"], d["right_n"])
        fallbacks = d["fallbacks_used"]
        if n_min >= 2:
            base = 0.85
        elif n_min == 1:
            base = 0.65
        else:
            base = 0.30
        lr_dev = abs(lr_pct - 50)
        tb_dev = abs(tb_pct - 50)
        if lr_dev < 5 and tb_dev < 5:
            base += 0.10
        elif (lr_dev > 25 or tb_dev > 25) and n_min < 2:
            # 극단값 + 후보 적음 = 오탐 risk
            base *= 0.7
        base -= 0.10 * fallbacks
        conf = max(0.10, min(0.95, round(base, 2)))
        if fallbacks == 0 and n_min >= 1:
            source = "detected"
        elif fallbacks == 4:
            source = "fallback"
        else:
            source = "partial"
        return conf, source

    def analyze_centering(self, image) -> tuple[float, str, str, dict, float, str]:
        """P0-1: 추가 반환 = lines(dict), confidence(float), source(str)."""
        card = self._card_image_or_roi(image)
        card_gray = cv2.cvtColor(card, cv2.COLOR_BGR2GRAY)
        d = self._detect_inner_border_margins(card_gray)
        top_m, bottom_m, left_m, right_m = d["top_m"], d["bottom_m"], d["left_m"], d["right_m"]

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

        conf, source = self._centering_confidence_source(d, float(lp), float(tp))
        lines = {
            "left_x": d["left_x_norm"],
            "right_x": d["right_x_norm"],
            "top_y": d["top_y_norm"],
            "bottom_y": d["bottom_y_norm"],
        }
        return score, detail, ratio, lines, conf, source

    def analyze_corner(self, image) -> float:
        """Codex 진단 후 수정 — false positive HIGH 산식 fix.
        - whitening dead zone (≤ 0.08): 감점 0
        - linear 구간 (0.08 ~ 0.25): 점진적 감점
        - 단일 코너 penalty cap = 2.0
        - score floor = 5.0 (확정 ROI)
        - blur_penalty 약화 (× 0.5)"""
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
        whitening_ratio = float(np.count_nonzero(white_mask) / white_mask.size)

        if whitening_ratio <= 0.08:
            whitening_penalty = 0.0
        else:
            whitening_penalty = ((whitening_ratio - 0.08) / 0.17) * 2.0
            whitening_penalty = max(0.0, min(2.0, whitening_penalty))

        gray_tip = cv2.cvtColor(tip, cv2.COLOR_BGR2GRAY)
        lap_var = float(cv2.Laplacian(gray_tip, cv2.CV_64F).var()) if gray_tip.size else 0.0
        blur_penalty = max(0.0, (80.0 - lap_var) / 80.0) * 1.0

        score = 10.0 - whitening_penalty - blur_penalty
        score = max(5.0, min(10.0, score))
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

    _METRIC_LABEL_KO = {
        "centering": "센터링",
        "corner": "코너",
        "surface": "표면",
        "whitening": "화이트닝",
        "edge": "엣지",
    }

    _CORNER_POSITION_KO = {
        "top_left": "좌상단",
        "top_right": "우상단",
        "bottom_left": "좌하단",
        "bottom_right": "우하단",
    }

    @classmethod
    def _positionKo(cls, pos: str) -> str:
        return cls._CORNER_POSITION_KO.get(pos, pos)

    @classmethod
    def calculate_grade(cls, weighted_raw: float, metrics: dict, has_major: bool):
        """spec § 3 — 9단계 cap (weakest link rule). 역호환 wrapper."""
        grade, color, _ = cls.calculate_grade_with_trace(weighted_raw, metrics, has_major)
        return grade, color

    @classmethod
    def calculate_grade_with_trace(cls, weighted_raw: float, metrics: dict, has_major: bool):
        """P0-1: weakest-link rule + decision trace.
        Returns (grade, color, trace_dict)."""
        # weighted 만 기준 등급 (min_metric 무시) — 사용자 납득용
        raw_grade = cls._DEFAULT_GRADE[0]
        for g, w_thr, _, _ in cls._GRADE_TABLE:
            if weighted_raw >= w_thr:
                raw_grade = g
                break

        # final grade (weakest-link + has_major)
        final_grade, final_color = cls._DEFAULT_GRADE
        for g, w_thr, m_thr, color in cls._GRADE_TABLE:
            if weighted_raw < w_thr:
                continue
            if metrics and min(metrics.values()) < m_thr:
                continue
            if g in ("S+", "S") and has_major:
                continue
            final_grade, final_color = g, color
            break

        # min metric
        min_metric_name = min(metrics, key=metrics.get) if metrics else None
        min_metric_score = float(metrics[min_metric_name]) if min_metric_name else 0.0

        caps = []
        if raw_grade != final_grade:
            if min_metric_name is not None:
                label = cls._METRIC_LABEL_KO.get(min_metric_name, min_metric_name)
                caps.append({
                    "type": "min_metric_cap",
                    "metric": min_metric_name,
                    "metric_score": round(min_metric_score, 1),
                    "raw_grade": raw_grade,
                    "final_grade": final_grade,
                    "message": f"{label} {min_metric_score:.1f}점 기준 최종 등급 {final_grade}로 제한",
                })
            if has_major and raw_grade in ("S+", "S"):
                caps.append({
                    "type": "major_defect",
                    "raw_grade": raw_grade,
                    "final_grade": final_grade,
                    "message": "심각한 결함 감지 — S/S+ 등급 강등",
                })

        trace = {
            "raw_grade_by_weight": raw_grade,
            "final_grade": final_grade,
            "min_metric_name": min_metric_name,
            "min_metric_score": round(min_metric_score, 1),
            "caps_applied": caps,
        }
        return final_grade, final_color, trace

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

    # Phase 2-B Step 2 — bbox NMS / merge helper.
    # 같은 type 끼리 (IoU > iou_thr) OR (center distance < center_thr × max_dim) OR
    # (한 쪽이 다른 쪽 contained) 면 confidence 큰 쪽 keep.
    @staticmethod
    def _merge_regions(regions: list, iou_thr: float = 0.2,
                       center_thr: float = 0.75) -> list:
        if not regions:
            return regions

        def iou(a, b):
            ax, ay, aw, ah = a["bbox"]
            bx, by, bw, bh = b["bbox"]
            x1, y1 = max(ax, bx), max(ay, by)
            x2 = min(ax + aw, bx + bw)
            y2 = min(ay + ah, by + bh)
            if x2 <= x1 or y2 <= y1:
                return 0.0
            inter = (x2 - x1) * (y2 - y1)
            union = aw * ah + bw * bh - inter
            return inter / union if union > 0 else 0.0

        def contained(a, b):
            ax, ay, aw, ah = a["bbox"]
            bx, by, bw, bh = b["bbox"]
            return (ax >= bx and ay >= by and ax + aw <= bx + bw
                    and ay + ah <= by + bh)

        def near_center(a, b):
            ax, ay, aw, ah = a["bbox"]
            bx, by, bw, bh = b["bbox"]
            acx, acy = ax + aw / 2, ay + ah / 2
            bcx, bcy = bx + bw / 2, by + bh / 2
            dist = ((acx - bcx) ** 2 + (acy - bcy) ** 2) ** 0.5
            max_dim = max(aw, ah, bw, bh)
            return max_dim > 0 and dist < center_thr * max_dim

        # confidence 내림차순 → 같은 type 끼리만 merge.
        # Codex 사후: near_center 단독 suppress 는 다른 위치 결함을 합칠 risk →
        # (IoU>0 OR contained) AND near_center 로 정정.
        sorted_regions = sorted(regions, key=lambda r: -r.get("confidence", 0.0))
        kept = []
        for r in sorted_regions:
            rt = r.get("type")
            dup = False
            for k in kept:
                if k.get("type") != rt:
                    continue
                center_dup = near_center(r, k) and (
                    iou(r, k) > 0.0
                    or contained(r, k) or contained(k, r))
                if (iou(r, k) > iou_thr
                        or contained(r, k) or contained(k, r)
                        or center_dup):
                    dup = True
                    break
            if not dup:
                kept.append(r)
        return kept

    # P0-C hotfix issue 4: 화이트닝 ROI = 카드 외곽 10% band 만.
    # 사용자 명시: 테두리의 작은 흰 점/색 빠짐 검출. 전체 카드 큰 마스크 X.
    _WHITENING_BAND_RATIO = 0.10  # 외곽 10%

    def detect_whitening_regions(self, card_roi) -> list:
        """spec § 2 — HSV S 부스트 → 흰 영역 highlight → bbox list.
        P0-C hotfix: 테두리 band 만 분석 + 작은 connected component + 위치 label.
        사용자 명시 영상 = 오른쪽 테두리의 작은 흰 점/색 빠짐 검출 목표."""
        if card_roi is None or card_roi.size == 0:
            return []
        hsv = cv2.cvtColor(card_roi, cv2.COLOR_BGR2HSV).astype(np.float32)
        hsv[:, :, 1] = np.clip(hsv[:, :, 1] * 2.0, 0, 255)
        boosted = cv2.cvtColor(hsv.astype(np.uint8), cv2.COLOR_HSV2BGR)
        diff = cv2.absdiff(boosted, card_roi)
        mask = (diff.sum(axis=2) > 75).astype(np.uint8) * 255
        h, w = mask.shape
        total_pixels = float(h * w)

        # P0-C hotfix: outer band mask. 안쪽 영역 (로고/포켓볼/illustration) 제외.
        band = max(8, int(min(h, w) * self._WHITENING_BAND_RATIO))
        band_mask = np.zeros((h, w), dtype=np.uint8)
        band_mask[:band, :] = 255
        band_mask[-band:, :] = 255
        band_mask[:, :band] = 255
        band_mask[:, -band:] = 255
        mask = cv2.bitwise_and(mask, band_mask)

        # P0-C hotfix: 작은 connected component (점/얇은 영역) 만.
        # 큰 영역 (반사광 / 큰 색 변화) 제외.
        min_area = max(15, int(total_pixels * 0.00005))   # 매우 작은 점도 검출
        max_area = int(total_pixels * 0.003)              # 큰 반사광 제외

        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL,
                                       cv2.CHAIN_APPROX_SIMPLE)
        regions = []
        for c in contours:
            area = float(cv2.contourArea(c))
            if area < min_area or area > max_area:
                continue
            x, y, cw, ch = cv2.boundingRect(c)
            area_ratio = area / total_pixels
            confidence = min(0.85, area_ratio * 200.0)  # 작은 점이라 boost
            if confidence < 0.10:
                continue

            # 위치 label (상/하/좌/우 테두리)
            cx_n = (x + cw / 2) / w
            cy_n = (y + ch / 2) / h
            band_n = self._WHITENING_BAND_RATIO
            if cy_n < band_n:
                position = "상단 테두리"
            elif cy_n > 1 - band_n:
                position = "하단 테두리"
            elif cx_n < band_n:
                position = "좌측 테두리"
            else:
                position = "우측 테두리"

            regions.append({
                "bbox": (x / w, y / h, cw / w, ch / h),
                "type": "whitening",
                "position_label": position,
                "confidence": float(round(confidence, 2)),
                "area_ratio": float(round(area_ratio, 4)),
            })
        # NMS merge + cap 10
        merged = self._merge_regions(regions)
        for r in merged:
            ar = r.get("area_ratio", 0.0)
            r["_sev_rank"] = 2 if ar > 0.01 else (1 if ar > 0.003 else 0)
        merged.sort(key=lambda r: (
            -r.get("_sev_rank", 0),
            -r.get("confidence", 0.0),
            -r.get("area_ratio", 0.0),
            r.get("bbox", (0.0, 0.0, 0.0, 0.0)),
        ))
        return merged[:10]

    # Phase 2-B Step 2 — artwork interior border (정규화 좌표).
    # 카드 테두리 ~6% → 0.08 안쪽 = artwork interior 로 분류 stricter 기준 적용.
    _ARTWORK_BORDER = 0.08

    def detect_scratch_regions(self, card_roi) -> list:
        """spec § 2 — CLAHE local contrast → 선형(스크래치) / 점형(찍힘) 패턴.
        Phase 2-B Step 2: threshold ↑ + artwork interior stricter + NMS + cap 20."""
        if card_roi is None or card_roi.size == 0:
            return []
        lab = cv2.cvtColor(card_roi, cv2.COLOR_BGR2LAB)
        l_channel = lab[:, :, 0]
        clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(l_channel)
        diff = cv2.absdiff(enhanced, l_channel)
        # Codex 사전: 40→50 (75 권장은 너무 강함, FN 위험)
        mask = (diff > 50).astype(np.uint8) * 255
        h, w = mask.shape
        total_pixels = float(h * w)
        contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL,
                                       cv2.CHAIN_APPROX_SIMPLE)
        border = self._ARTWORK_BORDER
        regions = []
        for c in contours:
            x, y, cw, ch = cv2.boundingRect(c)
            # Codex 사전: min size 4→6 (16px → 36px)
            if cw < 6 or ch < 6:
                continue
            aspect = max(cw / max(ch, 1), ch / max(cw, 1))
            area = float(cv2.contourArea(c))
            if aspect > 4.0 and area > 80:
                rtype = "scratch"
            elif 1.0 <= aspect <= 4.0 and 40 <= area < 250:
                rtype = "dent"
            else:
                continue
            # artwork interior 추가 stricter — bbox 전체가 (border ~ 1-border)
            # 사각형 내부면 area > 150 + confidence ≥ 0.30 만 통과.
            # Codex 사후: 중심 기준은 외곽 걸친 bbox 도 stricter 적용 risk → bbox 전체.
            x1_norm = x / w
            y1_norm = y / h
            x2_norm = (x + cw) / w
            y2_norm = (y + ch) / h
            in_artwork = (border <= x1_norm and x2_norm <= 1 - border
                          and border <= y1_norm and y2_norm <= 1 - border)
            confidence = min(0.85, area / (total_pixels * 0.005))
            # Codex 사전: confidence floor 0.20
            if confidence < 0.20:
                continue
            if in_artwork and (area < 150 or confidence < 0.30):
                continue
            regions.append({
                "bbox": (x / w, y / h, cw / w, ch / h),
                "type": rtype,
                "confidence": float(round(confidence, 2)),
                "area": float(round(area, 1)),
            })
        # NMS merge + cap 20 (severity moderate/minor 산정 후 sort)
        merged = self._merge_regions(regions)
        for r in merged:
            r["_sev_rank"] = 1 if r.get("confidence", 0.0) > 0.6 else 0
        # Codex 사후: bbox tuple tie-breaker 로 deterministic 순서 보장.
        merged.sort(key=lambda r: (
            -r.get("_sev_rank", 0),
            -r.get("confidence", 0.0),
            -r.get("area", 0.0),
            r.get("bbox", (0.0, 0.0, 0.0, 0.0)),
        ))
        return merged[:20]

    @staticmethod
    def _detect_card_side(warped_card):
        """P0-A hotfix: 사용자 명시 정책 — confidence 낮음 ≠ front 확신.
        front detector 단순 alg (hue std) = fixture 검증 실패 (back 사진도 hue 다양).
        → back detector 만 단방향. 애매하면 None (low_detection).

        Returns (side, signals) where side ∈ {"back", None}.
        side="back" → back 확신 high. None → 애매 (front 가능성 단정 X).
        """
        if warped_card is None or warped_card.size == 0:
            return None, {"back": 0.0, "blue_ratio": 0.0, "yellow_ratio": 0.0}
        h, w = warped_card.shape[:2]
        if h < 20 or w < 20:
            return None, {"back": 0.0, "blue_ratio": 0.0, "yellow_ratio": 0.0}
        hsv = cv2.cvtColor(warped_card, cv2.COLOR_BGR2HSV)
        total = float(h * w)

        # back signal — 파란 wave + 노란 로고 dominance
        blue_mask = cv2.inRange(hsv, np.array([100, 80, 80]), np.array([135, 255, 255]))
        blue_ratio = float(np.count_nonzero(blue_mask)) / total
        yellow_mask = cv2.inRange(hsv, np.array([20, 120, 120]), np.array([35, 255, 255]))
        yellow_ratio = float(np.count_nonzero(yellow_mask)) / total
        back_signal = min(1.0, blue_ratio * 1.5 + yellow_ratio * 2.0)

        # back 확신 = signal >= 0.50 AND raw threshold 둘 다 통과 (보수적)
        if back_signal >= 0.50 and blue_ratio > 0.20 and yellow_ratio > 0.05:
            side = "back"
        else:
            side = None  # 애매 — front 단정 X

        signals = {
            "back": round(back_signal, 2),
            "blue_ratio": round(blue_ratio, 3),
            "yellow_ratio": round(yellow_ratio, 3),
        }
        return side, signals

    @staticmethod
    def _is_card_back(warped_card) -> tuple[bool, float]:
        """역호환 wrapper — _detect_card_side 사용 권장."""
        if warped_card is None or warped_card.size == 0:
            return False, 0.0
        h, w = warped_card.shape[:2]
        if h < 20 or w < 20:
            return False, 0.0
        hsv = cv2.cvtColor(warped_card, cv2.COLOR_BGR2HSV)
        total = float(h * w)
        blue_mask = cv2.inRange(hsv, np.array([100, 80, 80]), np.array([135, 255, 255]))
        blue_ratio = float(np.count_nonzero(blue_mask)) / total
        yellow_mask = cv2.inRange(hsv, np.array([20, 120, 120]), np.array([35, 255, 255]))
        yellow_ratio = float(np.count_nonzero(yellow_mask)) / total
        # back 패턴: 파란색 dominance + 노란 로고 일부
        is_back = blue_ratio > 0.20 and yellow_ratio > 0.05
        confidence = min(1.0, blue_ratio * 1.5 + yellow_ratio * 2.0)
        return is_back, round(confidence, 2)

    def precheck(self, image, side: str = "front", frame_hint=None) -> dict:
        """촬영 직후 lightweight 품질 게이트. /analyze 전 per-side 검증용.
        score / reason_code / quality 만 반환. deduction/grade 생성 X."""
        if image is None or image.size == 0:
            return self._precheck_result(side, False, "bad", "card_not_detected",
                "카드를 찾지 못했어요", "프레임에 카드를 맞춰 다시 촬영해 주세요",
                blur=0.0, glare=0.0, exposure=0.0, roi=0.0)

        details = self._find_card_rect_details(image, frame_hint=frame_hint)
        warped = details["warped"]
        det_conf = float(details.get("area_ratio", 0.0))
        if warped is None or warped.size == 0:
            return self._precheck_result(side, False, "bad", "card_not_detected",
                "카드를 찾지 못했어요", "프레임에 카드를 맞춰 다시 촬영해 주세요",
                blur=0.0, glare=0.0, exposure=0.0, roi=det_conf)

        gray = cv2.cvtColor(warped, cv2.COLOR_BGR2GRAY)
        lap_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())
        blur_score = min(1.0, lap_var / 200.0)

        hsv = cv2.cvtColor(warped, cv2.COLOR_BGR2HSV)
        v = hsv[:, :, 2]
        v_mean = float(v.mean())
        exposure_score = 1.0 - min(1.0, abs(v_mean - 140.0) / 140.0)
        overexp_ratio = float((v > 250).sum()) / float(v.size)

        bright_mask = (v > 245).astype(np.uint8) * 255
        contours, _ = cv2.findContours(bright_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        glare_area_ratio = (max([cv2.contourArea(c) for c in contours]) / float(v.size)
                            if contours else 0.0)
        glare_score = 1.0 - min(1.0, glare_area_ratio / 0.15)

        roi_quality = float(details.get("ratio", 0.0))
        roi_score = min(1.0, roi_quality / 0.75) if roi_quality > 0 else 0.5

        # 뒷면은 균일한 갤럭시 패턴이라 lap_var 가 본질적으로 낮음 → side별 reject threshold.
        # (앞면은 아트/텍스트/홀로로 고주파 풍부, 뒷면은 그렇지 않음 — 동일 30 적용 시 초점 맞은 뒷면도 오판)
        blur_reject = 12.0 if side == "back" else 30.0
        if lap_var < blur_reject:
            return self._precheck_result(side, False, "bad", "blur",
                "사진이 선명하지 않아요", "카드를 한 손으로 고정한 뒤 다시 촬영해 주세요",
                blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)
        if v_mean < 60:
            return self._precheck_result(side, False, "bad", "under_exposed",
                "촬영 환경이 너무 어두워요", "밝은 곳에서 다시 촬영해 주세요",
                blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)
        if overexp_ratio > 0.30:
            return self._precheck_result(side, False, "bad", "over_exposed",
                "사진이 너무 밝아요", "직사광선/플래시를 피해 다시 촬영해 주세요",
                blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)
        if glare_area_ratio > 0.12:
            return self._precheck_result(side, False, "bad", "glare",
                "카드 표면에 빛 반사가 강해요", "각도를 바꿔 다시 촬영해 주세요",
                blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)

        # P0-B: analyze 단계의 det_conf < 0.40 retake 를 precheck 시점으로 끌어올림.
        # 결과 화면 진입 전 차단 — 사용자가 2장 다 찍은 뒤 retake 보지 X.
        area_ratio = float(details.get("area_ratio", 0.0))
        if area_ratio < 0.40:
            return self._precheck_result(side, False, "bad", "low_detection",
                "카드 외곽 검출이 약해요",
                "카드가 프레임 안에 잘 들어오도록 다시 촬영해 주세요",
                blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)

        # 면 검사 = "확실히 반대면일 때만" 차단(유연·앞뒤 대칭). _detect_card_side 는 back 만
        # 단방향 판정(None=애매)이라, 앞면 단계만 'back 확신' 시 차단한다.
        # ★뒷면 단계는 back 단정 요구를 제거: 탑로더/슬리브 글레어로 갤럭시 패턴(파랑+노랑)이
        #   흐려지면 back 확신이 안 잡혀 정상 뒷면이 자주 반려됐음(앞면은 동일 상황서 통과).
        #   앞면 단계의 wrong_side 가드 + 앞/뒷 동일파일 가드 + (앞면)신원검증이 잘못된 면을 거른다.
        side_detected, _side_signals = self._detect_card_side(warped)
        if side == "front" and side_detected == "back":
            # 앞면 단계인데 back 확신 → 잘못된 면
            return self._precheck_result(side, False, "bad", "wrong_side",
                "촬영한 면이 달라요",
                "뒷면이 보여요. 카드 앞면을 촬영해 주세요",
                blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)

        blur_warn = 22.0 if side == "back" else 50.0
        is_warning = (
            lap_var < blur_warn or v_mean < 80 or overexp_ratio > 0.15 or glare_area_ratio > 0.05
        )
        if is_warning:
            return self._precheck_result(side, True, "warning", "low_quality",
                "촬영 상태를 다시 확인해 주세요",
                "더 정확한 분석을 원하면 다시 촬영해 주세요",
                blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)

        return self._precheck_result(side, True, "good", None, None, None,
            blur=blur_score, glare=glare_score, exposure=exposure_score, roi=roi_score)

    @staticmethod
    def _precheck_result(side, ok, quality, code, title, message,
                         blur, glare, exposure, roi):
        return {
            "ok": ok,
            "side": side,
            "quality": quality,
            "reason_code": code,
            "reason_title": title,
            "reason_message": message,
            "blur_score": round(blur, 3),
            "glare_score": round(glare, 3),
            "exposure_score": round(exposure, 3),
            "roi_score": round(roi, 3),
        }

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
                "confidence": float(round(min(0.85, (9.0 - score) / 5.0), 2)),
            })
        return results

    def analyze(self, front, back, corners: list | None = None,
                frame_hint: tuple | None = None,
                debug: bool = False) -> AnalysisResult:
        """frame_hint = (fx, fy, fw, fh) normalized 0~1.
        Flutter capture screen 의 frame overlay 좌표 → backend 분석 ROI 기준.
        debug=True → /tmp/grading_debug/{session_id}/ 에 ROI/corner/mask/JSON 저장."""
        self._rect_cache = {}
        self._front_image_id = id(front)
        self._back_image_id = id(back)
        self._warped_front = self._find_card_rect(front, frame_hint=frame_hint)
        self._warped_back = self._find_card_rect(back, frame_hint=frame_hint)
        detection = self.detect_card_confidence(front, frame_hint=frame_hint)

        # ── Session 발급 (P0-C: prod 도 항상 evidence 위해 발급) ──
        # debug=True 면 풀 debug 파일 저장. debug=False 면 evidence 4종만 저장.
        session_id = self._new_session_id()
        debug_paths: dict = {}
        if debug:
            debug_paths["front_roi"] = self._debug_save_image(
                session_id, "front_roi.jpg", self._warped_front)
            debug_paths["back_roi"] = self._debug_save_image(
                session_id, "back_roi.jpg", self._warped_back)

        # Codex 진단 후 추가: warped 가 None 이면 점수 산출하지 않고 retake 반환.
        # 사용자 명시: 손/배경을 카드 손상으로 분석하지 않게 차단.
        if self._warped_front is None or self._warped_back is None:
            missing = []
            if self._warped_front is None:
                missing.append("앞면")
            if self._warped_back is None:
                missing.append("뒷면")
            reason = f"{'/'.join(missing)} 카드 외곽을 감지하지 못했어요"
            if debug and session_id is not None:
                self._write_debug_json(session_id, {
                    "session_id": session_id,
                    "total_score": 0.0,
                    "grade": "C",
                    "capture_quality": "bad",
                    "retake_required": True,
                    "retake_reason": f"{reason}. 프레임에 카드를 맞춰 다시 촬영해 주세요",
                    "warped_front_present": self._warped_front is not None,
                    "warped_back_present": self._warped_back is not None,
                    "detection_confidence": detection["confidence"],
                    "early_exit": "warped_none",
                    "debug_paths": debug_paths,
                })
            return AnalysisResult(
                centering_score=0.0,
                centering_ratio="",
                detection_confidence=detection["confidence"],
                corner_score=0.0,
                surface_score=0.0,
                whitening_score=0.0,
                edge_score=0.0,
                total_score=0.0,
                heavy_whitening=False,
                centering_detail="", corner_detail="",
                surface_detail="", whitening_detail="", edge_detail="",
                weighted_score=0.0,
                total_score_display=0.0,
                grade="C",
                grade_color="#95A5A6",
                deduction_reasons=[],
                defect_regions=[],
                has_major_defect=True,
                retake_required=True,
                retake_reason=f"{reason}. 프레임에 카드를 맞춰 다시 촬영해 주세요",
                capture_quality="bad",
                screen_suspected=False,
                screen_suspect_reason="",
            )

        (centering, centering_detail, centering_ratio,
         centering_lines, centering_conf, centering_source) = self.analyze_centering(front)
        # P0-fix-1: card_bbox + corner_regions front/back 각각 (back overlay 좌표 mismatch fix)
        front_details = self._find_card_rect_details(front, frame_hint=frame_hint)
        back_details = self._find_card_rect_details(back, frame_hint=frame_hint)
        front_card_bbox = self._compute_card_bbox(front, frame_hint, front_details)
        back_card_bbox = self._compute_card_bbox(back, frame_hint, back_details)
        card_bbox = {"front": front_card_bbox, "back": back_card_bbox}
        corner_regions = {
            "front": self._compute_corner_regions(front_card_bbox),
            "back": self._compute_corner_regions(back_card_bbox),
        }
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

        # Codex 진단: warped 가 frame_hint quad fallback 이면 ROI 신뢰성 낮음 → confidence × 0.3.
        front_fallback = self._rect_cache.get(
            (id(front), frame_hint) if frame_hint is not None else id(front), {}).get("from_frame_hint", False)
        back_fallback = self._rect_cache.get(
            (id(back), frame_hint) if frame_hint is not None else id(back), {}).get("from_frame_hint", False)

        def conf_for_side(side: str, raw: float) -> float:
            mult = 0.3 if (side == "front" and front_fallback) or (side == "back" and back_fallback) else 1.0
            return round(raw * mult, 2)

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
                penalty = round(min(2.0, max(0.0, 10.0 - c["score"])), 1)
                side_ko = "앞면" if side_name == "front" else "뒷면"
                pos_ko = self._positionKo(c["position"])
                add_reason(
                    "corner", side_name, c["position"], c["severity"],
                    conf_for_side(side_name, c["confidence"]), penalty, c["bbox"],
                    f"{side_ko} {pos_ko} 코너 마모 후보",
                    # P0-C hotfix issue 5: 사용자 친화 문구 (기술명 X)
                    f"{side_ko} {pos_ko} 코너의 마모/눌림 후보입니다",
                    "#E67E22",
                    region_type="corner_damage",
                )

        for w_region in self.detect_whitening_regions(warped_back):
            ar = w_region["area_ratio"]
            sev = "major" if ar > 0.02 else ("moderate" if ar > 0.005 else "minor")
            # P0-C hotfix issue 4 + 5: 위치 label + 사용자 친화 문구
            position_label = w_region.get("position_label", "테두리")
            add_reason(
                "whitening", "back", "", sev,
                conf_for_side("back", w_region["confidence"]),
                round(min(2.0, ar * 100.0), 1),
                w_region["bbox"],
                f"뒷면 {position_label} 백화 후보",
                f"뒷면 {position_label} 주변의 밝은 점/색 빠짐 후보입니다",
                "#3498DB",
            )

        for side_name, side_warped in (("front", warped_front), ("back", warped_back)):
            for s_region in self.detect_scratch_regions(side_warped):
                conf = conf_for_side(side_name, s_region["confidence"])
                sev = "moderate" if conf > 0.6 else "minor"
                is_scratch = s_region["type"] == "scratch"
                side_ko = "앞면" if side_name == "front" else "뒷면"
                label = f"{side_ko} 표면 {'스크래치' if is_scratch else '찍힘'} 후보"
                # P0-C hotfix issue 5: 사용자 친화 문구
                explanation = (
                    f"{side_ko} 표면의 얇은 선형 패턴 후보입니다"
                    if is_scratch
                    else f"{side_ko} 표면의 점형 찍힘 후보입니다"
                )
                add_reason(
                    s_region["type"], side_name, "", sev,
                    conf, 0.5 if is_scratch else 0.3,
                    s_region["bbox"], label,
                    explanation,
                    "#9B59B6",
                )

        # P0-C hotfix issue 1: 점수/감점 source of truth 통합.
        # hotfix 8 추가: confidence < 0.50 = 참고 후보 (penalty 0, 점수 영향 X).
        # 0.50~0.75 = 약한 감점 (×0.5). >= 0.75 = 정상 감점.
        # → 표면 33% 신뢰도 후보가 점수 박살 (4.8) 했던 문제 해결.
        for r in deduction_reasons:
            if r.confidence < 0.50:
                r.penalty = 0.0
            elif r.confidence < 0.75:
                r.penalty = round(r.penalty * 0.5, 2)

        corner_penalty = sum(r.penalty for r in deduction_reasons if r.type == "corner")
        surface_penalty = sum(r.penalty for r in deduction_reasons if r.type in ("scratch", "dent"))
        whitening_penalty = sum(r.penalty for r in deduction_reasons if r.type == "whitening")

        corner_avg = round(max(0.0, corner_avg - corner_penalty), 1)
        surface_avg = round(max(0.0, surface_avg - surface_penalty), 1)
        whitening_combined = round(max(0.0, whitening_combined - whitening_penalty), 1)

        # weighted_raw 재계산 (penalty 차감 후 metric)
        edge_score = round((corner_avg + surface_avg) / 2, 1)
        metrics_dict["corner"] = corner_avg
        metrics_dict["surface"] = surface_avg
        metrics_dict["whitening"] = whitening_combined
        metrics_dict["edge"] = edge_score
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

        has_major = self.has_major_defect(metrics_dict, deduction_reasons)
        grade, grade_color, grade_trace = self.calculate_grade_with_trace(
            weighted_raw, metrics_dict, has_major)
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

        retake_reasons_text = list(dict.fromkeys(retake_reasons_text))
        retake_required = len(retake_reasons_text) > 0
        if retake_required:
            capture_quality = "bad"
        elif det_conf < 0.55 or lighting_quality == "warning":
            capture_quality = "warning"
        else:
            capture_quality = "good"
        retake_reason = " / ".join(retake_reasons_text)

        # P0-C: evidence 4종 (warped + CLAHE + mask) 은 prod 도 항상 저장.
        # 사용자 결과 상세 sheet 의 토글 view 용. /grading/evidence/{session_id} 로 lazy fetch.
        if session_id is not None:
            debug_paths["surface_clahe_front"] = self._debug_save_image(
                session_id, "surface_clahe_front.jpg",
                self._build_clahe_visual(warped_front))
            debug_paths["surface_clahe_back"] = self._debug_save_image(
                session_id, "surface_clahe_back.jpg",
                self._build_clahe_visual(warped_back))
            debug_paths["whitening_mask_front"] = self._debug_save_image(
                session_id, "whitening_mask_front.jpg",
                self._build_whitening_mask_visual(warped_front))
            debug_paths["whitening_mask_back"] = self._debug_save_image(
                session_id, "whitening_mask_back.jpg",
                self._build_whitening_mask_visual(warped_back))
            if self._warped_front is not None:
                debug_paths["warped_front"] = self._debug_save_image(
                    session_id, "warped_front.jpg", warped_front)
            if self._warped_back is not None:
                debug_paths["warped_back"] = self._debug_save_image(
                    session_id, "warped_back.jpg", warped_back)

        # ── Debug 추가 단계별 save + JSON (debug=True 시만) ──
        if debug and session_id is not None:
            corner_names = [
                "front_corner_top_left", "front_corner_top_right",
                "front_corner_bottom_left", "front_corner_bottom_right",
                "back_corner_top_left", "back_corner_top_right",
                "back_corner_bottom_left", "back_corner_bottom_right",
            ]
            for i, c_img in enumerate(corners or []):
                if i < len(corner_names):
                    debug_paths[corner_names[i]] = self._debug_save_image(
                        session_id, f"{corner_names[i]}.jpg", c_img)

            self._write_debug_json(session_id, {
                "session_id": session_id,
                "total_score": total_score_display,
                "grade": grade,
                "capture_quality": capture_quality,
                "retake_required": retake_required,
                "retake_reason": retake_reason,
                "warped_front_present": warped_front is not None,
                "warped_back_present": warped_back is not None,
                "front_from_frame_hint": front_fallback,
                "back_from_frame_hint": back_fallback,
                "detection_confidence": detection["confidence"],
                "centering_score": centering,
                "corner_score": corner_avg,
                "surface_score": surface_avg,
                "whitening_score": whitening_combined,
                "edge_score": edge_score,
                "corner_scores_individual": corner_scores,
                "lighting_quality": lighting_quality,
                "lighting_issues_front": lighting_front.get("issues", []),
                "lighting_issues_back": lighting_back.get("issues", []),
                "deduction_reason_count": len(deduction_reasons),
                "deduction_reason_by_type": {
                    t: sum(1 for r in deduction_reasons if r.type == t)
                    for t in ("centering", "corner", "scratch", "dent",
                              "whitening", "surface", "edge")
                },
                "confidence_distribution": [round(r.confidence, 2) for r in deduction_reasons],
                "penalty_distribution": [round(r.penalty, 2) for r in deduction_reasons],
                "debug_paths": debug_paths,
            })

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
            # === P0-1 evidence layer ===
            card_bbox=card_bbox,
            centering_lines=centering_lines,
            centering_confidence=centering_conf,
            centering_source=centering_source,
            corner_regions=corner_regions,
            grade_decision_trace=grade_trace,
            # P0-C: evidence_session_id 를 Flutter 가 /grading/evidence/{id}/{layer} 호출 시 사용
            extra={"evidence_session_id": session_id} if session_id else {},
        )
