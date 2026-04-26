"""
가격 수집 메인 러너 (12시간 주기 실행)

실행:
    python collect_prices.py

포함 소스:
    - ICU (너정다): 실거래가
    - NAVER_SHOPPING: 현재 판매가
"""

import price_icu
import price_naver
from datetime import datetime


def main():
    print("=" * 60)
    print(f"가격 수집 시작: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)

    print("\n[1/2] ICU (너정다) 실거래가 수집")
    print("-" * 40)
    try:
        price_icu.collect()
    except Exception as e:
        print(f"[ICU 에러] {e}")

    print("\n[2/2] 네이버 쇼핑 판매가 수집")
    print("-" * 40)
    try:
        price_naver.collect()
    except Exception as e:
        print(f"[NAVER 에러] {e}")

    print("\n" + "=" * 60)
    print(f"수집 완료: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("=" * 60)


if __name__ == "__main__":
    main()
