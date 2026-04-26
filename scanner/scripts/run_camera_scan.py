import cv2
import sys
import os
import time
import numpy as np
import torch
import torchvision.transforms as T
from concurrent.futures import ThreadPoolExecutor
from PIL import Image, ImageFont, ImageDraw

sys.path.append(os.path.join(os.path.dirname(__file__), "..", ".."))

from scanner.app.ocr import CardOCR
from scanner.app.matcher import DBMatcher
from scanner.app.image_compare import ImageComparer

# ============================================================
# DINOv2 모델 초기화 (최초 1회 로드)
# ============================================================
print("[INIT] DINOv2 모델 로드 중...")
_dino_device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
_dino_model = torch.hub.load("facebookresearch/dinov2", "dinov2_vitb14")
_dino_model.eval()
_dino_model.to(_dino_device)

_dino_transform = T.Compose([
    T.Resize(256, interpolation=T.InterpolationMode.BICUBIC),
    T.CenterCrop(224),
    T.ToTensor(),
    T.Normalize(mean=[0.485, 0.456, 0.406], std=[0.229, 0.224, 0.225]),
])
print(f"[INIT] DINOv2 로드 완료 (device: {_dino_device})")


def extract_dino_vector(bgr_img: np.ndarray) -> list[float] | None:
    try:
        rgb = cv2.cvtColor(bgr_img, cv2.COLOR_BGR2RGB)
        pil_img = Image.fromarray(rgb)
        tensor = _dino_transform(pil_img).unsqueeze(0).to(_dino_device)
        with torch.no_grad():
            vec = _dino_model(tensor).squeeze(0).cpu().numpy()
        return vec.tolist()
    except Exception as e:
        print(f"[DINO ERROR] {e}")
        return None


# ============================================================
# 전역 상태
# ============================================================
global_is_scanning = False
global_recent_hit = None  # 확정된 카드명 (표시용)


def draw_korean_text(cv_img, text, pos, font_size, color_bgr):
    b, g, r = color_bgr
    img_pil = Image.fromarray(cv_img)
    draw = ImageDraw.Draw(img_pil)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/AppleGothic.ttf", font_size)
    except:
        font = ImageFont.load_default()
    draw.text(pos, text, font=font, fill=(b, g, r))
    return np.array(img_pil)


def get_guide_coords(w, h):
    box_h = int(h * 0.85)
    box_w = int(box_h / 1.396)
    x1 = (w - box_w) // 2
    y1 = (h - box_h) // 2
    return x1, y1, x1 + box_w, y1 + box_h


def check_focus(roi):
    gray = cv2.cvtColor(roi, cv2.COLOR_BGR2GRAY)
    score = cv2.Laplacian(gray, cv2.CV_64F).var()
    return score > 150.0, score


def background_scan_task(card_img, ocr_engine, db_matcher, img_comparer):
    """
    OCR 우선 인식 로직:
    1. 번호 읽히면 → 번호로 바로 확정
    2. 이름+번호 텍스트 점수 높으면 → 텍스트로 확정
    3. 텍스트 애매하면 → DINOv2로 추가 검증 (유사도 0.7 이상만)
    4. OCR 완전 실패 → DINOv2 단독 (유사도 0.85 이상 + SIFT 검증)
    """
    global global_is_scanning, global_recent_hit
    try:
        # --- 1단계: OCR ---
        ocr_name, ocr_number = ocr_engine.extract_text(card_img)
        print(f"\n[OCR] 이름: '{ocr_name}', 번호: '{ocr_number}'")

        # --- 2단계: 번호 직접 매칭 (가장 신뢰도 높음) ---
        if ocr_number and len(ocr_number) >= 3:
            result = db_matcher.search_by_number_exact(ocr_number)
            if result:
                global_recent_hit = f"{result['name']} ({result['number']})"
                print(f"[SUCCESS] 번호 직접 매칭: {result['name']}")
                return

        # --- 3단계: 이름+번호 텍스트 퍼지 매칭 ---
        if ocr_name or ocr_number:
            text_candidates = db_matcher.search_by_text(ocr_name, ocr_number, top_k=3)
            if text_candidates:
                best_text = text_candidates[0]

                # 텍스트 점수 충분 → 바로 확정
                if best_text['text_score'] >= 70:
                    global_recent_hit = f"{best_text['name']} ({best_text['number']})"
                    print(f"[SUCCESS] 텍스트 확정: {best_text['name']} ({best_text['text_score']:.0f}점)")
                    return

                # 텍스트 점수 애매 → DINOv2로 교차 검증
                if best_text['text_score'] >= 30:
                    dino_vec = extract_dino_vector(card_img)
                    if dino_vec:
                        image_candidates = db_matcher.search_by_image(dino_vec, top_k=5)
                        # 유사도 0.7 미만은 노이즈로 버림
                        image_candidates = [c for c in image_candidates if c['image_score'] >= 0.7]
                        if image_candidates:
                            print(f"[DINO] 이미지 1위: {image_candidates[0]['name']} ({image_candidates[0]['image_score']:.3f})")
                            merged = db_matcher.merge_candidates(text_candidates, image_candidates, top_k=1)
                            if merged and merged[0]['final_score'] >= 0.5:
                                best = merged[0]
                                global_recent_hit = f"{best['name']} ({best['number']})"
                                print(f"[SUCCESS] OCR+이미지 확정: {best['name']} (점수: {best['final_score']:.3f})")
                                return

        # --- 4단계: OCR 실패 → DINOv2 단독 (고신뢰도만) ---
        dino_vec = extract_dino_vector(card_img)
        if not dino_vec:
            return

        image_candidates = db_matcher.search_by_image(dino_vec, top_k=3)
        if not image_candidates or image_candidates[0]['image_score'] < 0.85:
            print(f"[DINO] 유사도 낮음 ({image_candidates[0]['image_score']:.3f if image_candidates else 0:.3f}), 미확정")
            return

        best = image_candidates[0]
        print(f"[DINO] 이미지 1위: {best['name']} ({best['image_score']:.3f})")

        # SIFT로 최종 검증
        if best.get('local_image_path'):
            vision_results = img_comparer.compare_to_candidates(card_img, [best['local_image_path']])
            if vision_results and vision_results[0]['score'] > 40:
                global_recent_hit = f"{best['name']} ({best['number']})"
                print(f"[SUCCESS] 이미지 단독 확정: {best['name']} (SIFT: {vision_results[0]['score']})")

    finally:
        global_is_scanning = False


def main():
    global global_is_scanning, global_recent_hit

    print("=" * 60)
    print("포켓몬 카드 스캐너 (카드 추적 + OCR 우선)")
    print("=" * 60)

    try:
        db_matcher = DBMatcher()
        img_comparer = ImageComparer()
        ocr_engine = CardOCR()
    except Exception as e:
        print(f"[초기화 에러] {e}")
        return

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        print("카메라를 열 수 없습니다.")
        return

    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 1280)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 720)

    executor = ThreadPoolExecutor(max_workers=1)
    print("\n카메라 연동 성공! 카드를 카메라에 보여주세요.")

    while True:
        ret, raw_frame = cap.read()
        if not ret:
            break

        h, w = raw_frame.shape[:2]
        x1, y1, x2, y2 = get_guide_coords(w, h)
        crop_img = raw_frame[y1:y2, x1:x2]

        is_focused, focus_score = check_focus(crop_img)
        box_color = (0, 255, 0) if is_focused else (0, 0, 255)
        thickness = 4 if is_focused else 2

        if is_focused and not global_is_scanning:
            global_is_scanning = True
            global_recent_hit = None
            executor.submit(background_scan_task, crop_img.copy(), ocr_engine, db_matcher, img_comparer)

        display_frame = raw_frame.copy()
        cv2.rectangle(display_frame, (x1, y1), (x2, y2), box_color, thickness)

        # OCR 영역 표시 (상단 이름, 하단 번호)
        y_name_end = y1 + int((y2 - y1) * 0.12)
        y_num_start = y1 + int((y2 - y1) * 0.90)
        cv2.rectangle(display_frame, (x1, y1), (x2, y_name_end), (255, 150, 0), 1)
        cv2.rectangle(display_frame, (x1, y_num_start), (x2, y2), (255, 150, 0), 1)

        if global_is_scanning:
            cv2.rectangle(display_frame, (x1, y1 - 40), (x1 + 320, y1), (0, 0, 0), -1)
            cv2.putText(display_frame, "ANALYZING...", (x1 + 10, y1 - 12),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        else:
            status = "READY" if is_focused else "ALIGN CARD"
            color = (0, 255, 0) if is_focused else (0, 0, 255)
            cv2.rectangle(display_frame, (x1, y1 - 40), (x1 + 280, y1), (0, 0, 0), -1)
            cv2.putText(display_frame, status, (x1 + 10, y1 - 12),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, color, 2)

        cv2.putText(display_frame, f"Focus: {focus_score:.0f}", (20, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, box_color, 2)

        if global_recent_hit:
            display_frame = draw_korean_text(
                display_frame, global_recent_hit, (x1, y2 + 10), 36, (0, 255, 255)
            )

        cv2.imshow("Pokemon Card Scanner", display_frame)

        if cv2.waitKey(1) & 0xFF == ord('q'):
            break

    cap.release()
    cv2.destroyAllWindows()
    executor.shutdown(wait=False)


if __name__ == "__main__":
    main()
