import cv2


class ImageComparer:
    def __init__(self):
        # SIFT: 홀로그램(빛반사) 노이즈에 강한 특징점 추출기 (ORB 대비 조명 변화/회전에 강력)
        self.sift = cv2.SIFT_create()
        # SIFT는 유클리드 거리(NORM_L2) 사용
        self.bf = cv2.BFMatcher(cv2.NORM_L2)

    def compare_to_candidates(self, query_img, candidate_paths):
        """
        쿼리 이미지(카메라 프레임)를 DB 후보 이미지들과 SIFT로 비교해
        가장 기하학적 매칭이 높은 순서로 정렬된 결과 반환
        """
        if query_img is None:
            return []

        query_gray = cv2.cvtColor(query_img, cv2.COLOR_BGR2GRAY)
        kp1, des1 = self.sift.detectAndCompute(query_gray, None)

        if des1 is None or len(kp1) < 10:
            return []

        results = []
        for path in candidate_paths:
            img2 = cv2.imread(path, cv2.IMREAD_GRAYSCALE)
            if img2 is None:
                continue

            kp2, des2 = self.sift.detectAndCompute(img2, None)
            if des2 is None or len(kp2) < 10:
                continue

            try:
                matches = self.bf.knnMatch(des1, des2, k=2)
                # Lowe's ratio test (SIFT 전용 임계값 0.75)
                good = [m for m, n in matches if m.distance < 0.75 * n.distance]
                results.append({"path": path, "score": len(good)})
            except Exception as e:
                print(f"Vision comparison error on {path}: {e}")

        results.sort(key=lambda x: x['score'], reverse=True)
        return results
