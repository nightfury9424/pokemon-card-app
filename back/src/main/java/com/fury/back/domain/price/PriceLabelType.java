package com.fury.back.domain.price;

/**
 * KO 가격 신뢰도/출처 표시 라벨 (display-layer 전용 — 가격값에 절대 영향 없음).
 *
 * 화면에 보이는 KO 가격 분기와 1:1로 일치시킨다.
 *  - isPromoExclusive 카드 = 해외 RAW/PSA 직접가를 그대로 노출 (KO 추정 모델 미적용) → OVERSEAS_REF
 *  - 그 외 = FORMULA / KO_ESTIMATED 알고리즘 추정 → ESTIMATED
 *
 * DOMESTIC_REAL / DOMESTIC_FEW(국내 실거래 기반)는 domesticCount(국내 실거래 수) 배선 후 발화.
 * 현재 domesticCount는 0 stub이라 두 tier는 비활성 — 후속 신뢰도 칩 작업(#2)에서 점등하면
 * 프론트 contract 변경 없이 그대로 켜진다.
 */
public enum PriceLabelType {
    DOMESTIC_REAL,  // 한국 실거래 충분 (n>=5)
    DOMESTIC_FEW,   // 한국 실거래 적음 (n1-4)
    ESTIMATED,      // 해외 시세 기반 KO 예상 가치 (알고리즘 추정)
    OVERSEAS_REF;   // 해외 직접 참고가 (프로모 등, KO 모델 미적용)

    /**
     * @param promoExclusive 해외 직접가 노출 카드 여부 (Card.isPromoExclusive)
     * @param domesticCount  국내 실거래 수 (현재 0 stub). null/0이면 DOMESTIC_* 비발화.
     */
    public static PriceLabelType resolve(boolean promoExclusive, Integer domesticCount) {
        if (domesticCount != null && domesticCount >= 5) return DOMESTIC_REAL;
        if (domesticCount != null && domesticCount >= 1) return DOMESTIC_FEW;
        if (promoExclusive) return OVERSEAS_REF;
        return ESTIMATED;
    }
}
