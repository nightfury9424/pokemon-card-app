import sys
import os

# app 모듈 임포트를 위한 경로 설정
sys.path.append(os.path.join(os.path.dirname(__file__), "..", ".."))

from scanner.app.matcher import DBMatcher

def main():
    print("============================================================")
    print("🧠 Phase 2: DB 매칭 엔진(Fuzzy Matcher) PoC 테스트")
    print("============================================================")
    
    # 1. 엔진 초기화 (수만 장의 카드를 0.1초 만에 메모리로 로딩)
    print("🔄 초기화 중...")
    matcher = DBMatcher()
    
    # 2. 가상의 OCR 오인식 테스트 케이스 (사용자가 가지고 있는 테스트 3장 활용)
    # 실제 OCR이 완벽하지 않다고 가정하고 글자를 살짝 꼬아서 대조합니다.
    test_cases = [
        # 사용자가 요청한 테스트 카드 3장
        {"name": "블래키V", "number": "084/069"},    # 완벽한 OCR 인식 가정
        {"name": "리자몽EX", "number": "331/19O"},   # 번호 오인식 (190의 0을 알파벳 O로 잘못 읽음)
        {"name": "난전의패기", "number": "236/172"}, # 이름 오인식 (천 -> 전)
        {"name": "토대부기", "number": "4/60"},      # 번호 포맷 불일치 (04/60 -> 4/60)
        {"name": "", "number": "084/069"},           # 번호만 겨우 읽은 최악의 케이스
        {"name": "난천의 패기", "number": ""},       # 이름만 겨우 읽은 최악의 케이스
    ]
    
    print("\n[테스트 시작]")
    for i, tc in enumerate(test_cases, 1):
        print(f"\n▶ 테스트 {i}: 카메라 OCR 추출 텍스트 -> [이름: '{tc['name']}', 번호: '{tc['number']}']")
        
        # 초고속 검색
        candidates = matcher.search_candidates(tc['name'], tc['number'], top_k=3)
        
        if not candidates:
            print("   ❌ 후보를 전혀 찾지 못했습니다.")
            continue
            
        for rank, cand in enumerate(candidates, 1):
            star = "⭐️(이미지확보됨!)" if cand['local_image_path'] else "  (캐싱안됨)"
            print(f"   {rank}위 (점수: {cand['score']:>4}점) {star} | {cand['name']} ({cand['number']}) | 코드: {cand['code']}")

if __name__ == "__main__":
    main()
