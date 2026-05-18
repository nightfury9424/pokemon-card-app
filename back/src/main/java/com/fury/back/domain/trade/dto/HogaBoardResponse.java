package com.fury.back.domain.trade.dto;

import java.util.List;

/**
 * 카드 상세 호가창 응답.
 *
 * <p>매도(ASK) 5행 + 매수(BID) 5행. UI는 ASK 위쪽(가격 내림차순), BID 아래쪽(가격 내림차순).
 *
 * @param cardId      카드 ID
 * @param status      호가 필터 상태 (RAW / PSA10 / BRG)
 * @param tickUnit    marketPrice 기준 tick 단위 (Flutter 등록 모달이 참고)
 * @param marketPrice KO 추정가 (시세 정책). null 이면 미산출
 * @param lowestAsk   가장 낮은 매도 가격. null=매도 호가 0건
 * @param highestBid  가장 높은 매수 가격. null=매수 호가 0건
 * @param askCount    전체 활성 매도 호가 건수
 * @param bidCount    전체 활성 매수 호가 건수
 * @param asks        매도 호가 행 (가격 내림차순)
 * @param bids        매수 호가 행 (가격 내림차순)
 */
public record HogaBoardResponse(
        String cardId,
        HogaStatusValue status,
        long tickUnit,
        Long marketPrice,
        Long lowestAsk,
        Long highestBid,
        long askCount,
        long bidCount,
        List<HogaLevelResponse> asks,
        List<HogaLevelResponse> bids) {

    /** JSON 직렬화용 status enum 별칭 (외부 노출 안전성). */
    public enum HogaStatusValue {
        RAW,
        PSA,
        BRG
    }
}
