// 호가 가격대별 tick 단위 — back/HogaTickResolver.java 와 동일 알고리즘.
//
// 가격대 → tick:
//   < 100,000원              → 1,000원
//   100,000 ~ 1,000,000     → 5,000원
//   1,000,000 ~ 10,000,000  → 10,000원
//   10,000,000 이상         → 100,000원
//
// 등록 시점에 isValidHogaTick로 검증. UI에서는 roundToHogaTick으로 사용자 입력 보정.

/// 가격대별 tick 단위 (KRW). 등록 모달/표시 양쪽에서 사용.
int hogaTick(int price) {
  if (price < 100000) return 1000;
  if (price < 1000000) return 5000;
  if (price < 10000000) return 10000;
  return 100000;
}

/// tick 단위 floor (bucket 계산용).
int floorToHogaTick(int price) => (price ~/ hogaTick(price)) * hogaTick(price);

/// tick 단위 round (사용자 입력 보정용).
int roundToHogaTick(int price) {
  final tick = hogaTick(price);
  return ((price / tick).round()) * tick;
}

/// 등록 검증용. 양수 + tick 단위 일치.
bool isValidHogaTick(int price) => price > 0 && price % hogaTick(price) == 0;
