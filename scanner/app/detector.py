import cv2
import numpy as np

class CardDetector:
    def __init__(self, width=630, height=880):
        # 포켓몬 카드의 고정된 실물 픽셀 비율 (가로세로 63:88 기준 고화질)
        self.width = width
        self.height = height

    def order_points(self, pts):
        """
        4개의 꼭짓점 좌표를 무조건 [좌상, 우상, 우하, 좌하] 순서로 정렬합니다.
        """
        rect = np.zeros((4, 2), dtype="float32")
        s = pts.sum(axis=1)
        rect[0] = pts[np.argmin(s)]
        rect[2] = pts[np.argmax(s)]

        diff = np.diff(pts, axis=1) # y - x
        rect[1] = pts[np.argmin(diff)]
        rect[3] = pts[np.argmax(diff)]
        return rect

    def find_and_warp_card(self, frame):
        """
        프레임 전체를 뒤져서 가장 '카드답게 생긴(비율 1.25~1.55)' 거대한 사각형을 찾은 뒤,
        사용자가 삐딱하게 들고 있거나 누워 있어도 완벽한 630x880 직사각형 뷰로 쭉 펴서 반환합니다.
        (CamScanner나 아이폰 문서 스캔 로직과 동일)
        """
        # 1. 전처리: 흑백, 블러링
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        blur = cv2.GaussianBlur(gray, (5, 5), 0)
        
        # 2. 노이즈 억제형 동적 Canny Edge 검출
        v = np.median(blur)
        sigma = 0.33
        lower = int(max(0, (1.0 - sigma) * v))
        upper = int(min(255, (1.0 + sigma) * v))
        edged = cv2.Canny(blur, lower, upper)
        
        # 3. 끊어진 카드 외곽선을 강제로 이어붙임
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
        closed = cv2.morphologyEx(edged, cv2.MORPH_CLOSE, kernel)

        # 4. 외곽선(Contour) 수집
        contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            return None, None
            
        # 가장 거대한 외곽선을 카드로 간주
        c = max(contours, key=cv2.contourArea)
        area = cv2.contourArea(c)
        
        # 화면의 최소 15% 이상을 차지해야 카드로 인정 (배경 노이즈 무시)
        if area < (frame.shape[0] * frame.shape[1] * 0.15): 
            return None, None
            
        # 5. 사용자의 손가락이 꼭짓점을 가려도 사각형을 추론해내는 minAreaRect 사용
        rect = cv2.minAreaRect(c)
        (center, (width, height), angle) = rect
        if width == 0 or height == 0:
            return None, None
            
        # 6. 비율 검사 (포켓몬 카드는 1.396의 비율을 가짐. 1.25 ~ 1.55까지만 허용)
        ratio = max(width, height) / min(width, height)
        if 1.25 <= ratio <= 1.55:
            box = cv2.boxPoints(rect)
            box = np.int32(box) # 카드 테두리를 그릴 4개의 다각형 꼭짓점
            
            pts = np.array(box, dtype="float32")
            ordered_pts = self.order_points(pts)
            tl, tr, br, bl = ordered_pts
            
            # 상단 변의 길이와 측면 변의 길이를 통해 카드가 화면에 <세워져> 있는지 <누워> 있는지 판단
            top_width = np.linalg.norm(tr - tl)
            side_height = np.linalg.norm(tr - br)
            
            # 카드가 누워서 화면에 잡힌 경우, 우선 누운 상태로 쫙 펴고 마지막에 소프트웨어적으로 90도 회전
            if top_width > side_height:
                dst = np.array([
                    [0, 0],
                    [self.height - 1, 0],
                    [self.height - 1, self.width - 1],
                    [0, self.width - 1]
                ], dtype="float32")
                M = cv2.getPerspectiveTransform(ordered_pts, dst)
                warped = cv2.warpPerspective(frame, M, (self.height, self.width))
                warped = cv2.rotate(warped, cv2.ROTATE_90_COUNTERCLOCKWISE)
            # 카드가 똑바로 세워져 있는 경우
            else:
                dst = np.array([
                    [0, 0],
                    [self.width - 1, 0],
                    [self.width - 1, self.height - 1],
                    [0, self.height - 1]
                ], dtype="float32")
                M = cv2.getPerspectiveTransform(ordered_pts, dst)
                warped = cv2.warpPerspective(frame, M, (self.width, self.height))
                
            # 타겟팅이 약간 어긋나는 것을 방지하기 위해 외곽선 5픽셀 강제 압축 크롭
            margin = 5
            warped = warped[margin:self.height-margin, margin:self.width-margin]
            
            return warped, box
            
        return None, None
