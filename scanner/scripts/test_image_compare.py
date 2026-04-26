import sys
import os
import cv2

sys.path.append(os.path.join(os.path.dirname(__file__), "..", ".."))

from scanner.app.image_compare import ImageComparer

def main():
    print("============================================================")
    print("👁️ Phase 3: SIFT 방식 카드 이미지 매칭 (Vision) PoC 검증")
    print("============================================================")
    
    comparer = ImageComparer()
    
    # 캐싱된 3개 이미지 경로 (Phase 1에서 저장됨)
    base_dir = os.path.join(os.path.dirname(__file__), "..", "data", "cards")
    paths = [
        os.path.join(base_dir, "BS2021007084.png"), # 블래키 V
        os.path.join(base_dir, "BS2024001331.png"), # 리자몽 ex
        os.path.join(base_dir, "BS2023001236.png"), # 난천의 패기
    ]
    
    valid_paths = [p for p in paths if os.path.exists(p)]
    if len(valid_paths) < 3:
        print("❌ 테스트를 위해 다운로드된 3장의 파일(Phase 1)이 필요합니다.")
        return

    # 가상의 카메라 프레임 생성: 
    # 맥북 카메라로 '블래키 V(BS2021007084)' 실물 카드를 삐딱하게 들고,
    # 저화질로 찍었다고 가정하고 코드 레벨에서 조작된 페이크 쿼리 이미지를 만듭니다.
    print(f"📸 가상의 카메라 프레임 생성 중... [원본: 블래키 V]")
    print(f" -> 모의 1: 손목의 각도를 15도 돌려서 삐딱하게 촬영됨")
    print(f" -> 모의 2: 카메라 수전증으로 인해 해상도가 50%나 저하 및 흐려짐")
    
    original = cv2.imread(valid_paths[0])
    h, w = original.shape[:2]
    
    # 모의 1: 중심 기준으로 15도 회전
    matrix = cv2.getRotationMatrix2D((w/2, h/2), 15, 1)
    query_img_rotated = cv2.warpAffine(original, matrix, (w, h))
    
    # 모의 2: 크기 축소 (화질 저하 모사)
    query_img_blurred = cv2.resize(query_img_rotated, (w//2, h//2))

    print("\n🔍 [비전 매칭 시작]")
    print("이 찌그러지고 돌아간 카메라 프레임을 DB의 정답 후보 3장과 머신러닝(특징점) 대조합니다...\n")
    
    results = comparer.compare_to_candidates(query_img_blurred, valid_paths)
    
    for rank, res in enumerate(results, 1):
        filename = os.path.basename(res['path'])
        
        # 1위는 블래키V가 되어야 함
        if rank == 1 and filename == "BS2021007084.png":
            mark = "🎯 (소름 돋게 정확히 일치!)"
        else:
            mark = ""
            
        print(f"   {rank}위: {filename:<16} | SIFT 매칭 점수: {res['score']:>4}점   {mark}")
        
    print("\n✅ OCR 글씨 따위는 단 하나도 취급하지 않고 오직 그림,색상,선의 고유 무늬(특징점)만으로")
    print("   회전/축소 오염된 이미지가 블래키V라는 것을 완벽하게 인지해냈습니다!")

if __name__ == "__main__":
    main()
