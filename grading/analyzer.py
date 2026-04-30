import cv2
import numpy as np
from models import AnalysisResult


class GradingAnalyzer:

    def _find_card_in_image(self, gray):
        """사진에서 카드 영역(bounding rect)을 찾아 반환. 실패시 전체 이미지 반환."""
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

    def analyze_centering(self, image) -> tuple[float, str]:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        cx, cy, cw, ch = self._find_card_in_image(gray)
        card_gray = gray[cy:cy + ch, cx:cx + cw]
        rh, rw = card_gray.shape

        sobel_y = cv2.Sobel(card_gray.astype(np.float32), cv2.CV_32F, 0, 1, ksize=3)
        sobel_x = cv2.Sobel(card_gray.astype(np.float32), cv2.CV_32F, 1, 0, ksize=3)
        row_grad = np.abs(sobel_y).mean(axis=1)
        col_grad = np.abs(sobel_x).mean(axis=0)

        outer_frac = 0.08
        fh = max(2, int(rh * outer_frac))
        fw = max(2, int(rw * outer_frac))

        top_m = int(np.argmax(row_grad[:fh]))
        bottom_m = fh - int(np.argmax(row_grad[-fh:]))
        left_m = int(np.argmax(col_grad[:fw]))
        right_m = fw - int(np.argmax(col_grad[-fw:]))

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

        lr_dev = abs(lp - 50)
        tb_dev = abs(tp - 50)
        if score >= 9.5:
            detail = "인쇄 여백 균일 — 감점 없음"
        elif score >= 8.0:
            detail = "경미한 센터링 불균형 감지"
        elif lr_dev >= tb_dev:
            detail = "좌우 센터링 불균형 감지 — 주요 감점 요인"
        else:
            detail = "상하 센터링 불균형 감지 — 주요 감점 요인"

        return score, detail

    def analyze_corner(self, image) -> float:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        h, w = gray.shape

        cy, cx = h // 2, w // 2
        region = gray[cy - h // 4:cy + h // 4, cx - w // 4:cx + w // 4]
        if region.size == 0:
            region = gray

        blurred = cv2.GaussianBlur(region, (3, 3), 0)
        edges = cv2.Canny(blurred, 30, 100)
        edge_density = np.count_nonzero(edges) / edges.size

        score = min(10.0, max(1.0, edge_density * 250))
        return round(score, 1)

    def analyze_surface(self, image) -> tuple[float, float]:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        cx, cy, cw, ch = self._find_card_in_image(gray)
        card_gray = gray[cy:cy + ch, cx:cx + cw]
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
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        cx, cy, cw, ch = self._find_card_in_image(gray)
        card = image[cy:cy + ch, cx:cx + cw]

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

    def analyze(self, front, back, corners: list) -> AnalysisResult:
        centering, centering_detail = self.analyze_centering(front)

        corner_scores = [self.analyze_corner(c) for c in corners]
        corner_avg = round(sum(corner_scores) / len(corner_scores), 1)
        min_cs = min(corner_scores)
        min_idx = corner_scores.index(min_cs)
        if min_cs >= 9.0:
            corner_detail = f"8개 코너 모두 양호 (평균 {corner_avg}점)"
        else:
            corner_detail = f"최저 {min_cs}점 ({self._CORNER_NAMES[min_idx]}) — 마모 감지"

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

        return AnalysisResult(
            centering_score=centering,
            corner_score=corner_avg,
            surface_score=surface_avg,
            whitening_score=whitening_combined,
            total_score=total,
            heavy_whitening=heavy,
            centering_detail=centering_detail,
            corner_detail=corner_detail,
            surface_detail=surface_detail,
            whitening_detail=whitening_detail,
        )
