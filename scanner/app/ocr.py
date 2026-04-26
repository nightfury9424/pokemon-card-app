import easyocr
import re
import cv2
import numpy as np

class CardOCR:
    def __init__(self):
        print("⏳ [CardOCR] 딥러닝 텍스트 인식(EasyOCR) 모델 로드 시작... (최초 1회, 수십 초 소요)")
        self.reader = easyocr.Reader(['ko', 'en'], gpu=False)
        print("✅ [CardOCR] EasyOCR 모델 로드 완료!")

    def _rotate(self, img, angle):
        if angle == 0:
            return img
        elif angle == 90:
            return cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)
        elif angle == 180:
            return cv2.rotate(img, cv2.ROTATE_180)
        elif angle == 270:
            return cv2.rotate(img, cv2.ROTATE_90_COUNTERCLOCKWISE)
        return img

    def _try_read(self, img_array):
        """
        카드 이미지에서 상단(이름)과 하단(번호) OCR.
        Returns: (name_str, number_str, total_confidence)
        """
        h, w = img_array.shape[:2]

        top_crop = img_array[0:int(h * 0.15), 0:w]
        bottom_crop = img_array[int(h * 0.85):h, 0:w]

        top_crop = cv2.resize(top_crop, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)
        bottom_crop = cv2.resize(bottom_crop, None, fx=2.0, fy=2.0, interpolation=cv2.INTER_CUBIC)

        top_gray = cv2.cvtColor(top_crop, cv2.COLOR_BGR2GRAY)
        bottom_gray = cv2.cvtColor(bottom_crop, cv2.COLOR_BGR2GRAY)

        top_results = self.reader.readtext(top_gray)
        bottom_results = self.reader.readtext(bottom_gray)

        num_pattern = re.compile(r"([0-9A-Za-zoOlLiI]{1,4})[/\\]([0-9A-Za-zoOlLiI]{1,4})")

        name_candidates = []
        total_conf = 0.0
        card_number = ""

        for (bbox, text, conf) in top_results:
            text = text.strip()
            if conf > 0.05 and len(text) >= 2 and not text.isdigit():
                name_candidates.append(text)
                total_conf += conf

        for (bbox, text, conf) in bottom_results:
            text = text.strip()
            if conf > 0.05:
                match = num_pattern.search(text)
                if match:
                    card_number = match.group(0)
                    total_conf += conf

        return " ".join(name_candidates), card_number, total_conf

    def extract_text(self, img_array):
        """
        4방향 회전 시도 후 가장 많은 텍스트가 읽힌 방향 사용.
        """
        best_name, best_number, best_conf = "", "", 0.0

        for angle in [0, 90, 270, 180]:
            rotated = self._rotate(img_array, angle)
            name, number, conf = self._try_read(rotated)

            # 번호 읽히면 가장 신뢰도 높음 → 즉시 반환
            if number:
                return name, number

            if conf > best_conf:
                best_conf = conf
                best_name = name
                best_number = number

        return best_name, best_number
