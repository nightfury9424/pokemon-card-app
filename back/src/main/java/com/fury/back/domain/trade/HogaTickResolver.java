package com.fury.back.domain.trade;

/**
 * 호가 가격대별 tick 단위 결정.
 *
 * <p>1,000원 고정은 4,000만원짜리 카드에 의미 없음 → 동적 tick.
 *
 * <pre>
 *   가격대              tick
 *   < 100,000원         1,000원
 *   100,000 ~ 1,000,000 5,000원
 *   1,000,000 ~ 10,000,000 10,000원
 *   10,000,000 이상     100,000원
 * </pre>
 *
 * <p>등록 시점에 tick 검증을 강제 (Controller에서 isValidTick 호출 → false면 reject).
 * Dart 측 hoga_tick.dart와 동일 알고리즘 유지.
 */
public final class HogaTickResolver {
    private HogaTickResolver() {}

    public static long resolve(long price) {
        if (price < 100_000L) return 1_000L;
        if (price < 1_000_000L) return 5_000L;
        if (price < 10_000_000L) return 10_000L;
        return 100_000L;
    }

    public static long floorToTick(long price) {
        long tick = resolve(price);
        return price / tick * tick;
    }

    public static long roundToTick(long price) {
        long tick = resolve(price);
        return Math.round((double) price / tick) * tick;
    }

    /** 양수 + tick 단위 일치 여부. 등록 검증용. */
    public static boolean isValidTick(long price) {
        return price > 0 && price % resolve(price) == 0;
    }
}
