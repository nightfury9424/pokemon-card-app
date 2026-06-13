package com.fury.back.domain.trade;

/**
 * 호가/거래 tick 단위 = 전 구간 100원 통일 (2026-06-13).
 *
 * <p>기존 가격대별 차등(1,000/5,000/10,000/100,000)은 200·500원 같은 정당한 저가까지
 * 막아 과했음 → 100원 단일 tick. `price % 100 == 0` 한 조건으로:
 * <ul>
 *   <li>차단: 1원·10원·50원(100 미달/비배수), 11111·222222·333333 등 junk(끝 00 아님)</li>
 *   <li>허용: 100원부터 100원 단위 — 200·500·1500·12300 …</li>
 * </ul>
 *
 * <p>등록 시점에 tick 검증을 강제 (Controller에서 isValidTick 호출 → false면 reject).
 * ★Dart 측 hoga_tick.dart도 동일하게 100원 통일 필요(다음 앱 릴리즈).
 */
public final class HogaTickResolver {
    private HogaTickResolver() {}

    /** 전 구간 100원 단위. */
    public static long resolve(long price) {
        return 100L;
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
