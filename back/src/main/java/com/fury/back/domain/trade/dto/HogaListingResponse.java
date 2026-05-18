package com.fury.back.domain.trade.dto;

import java.time.LocalDateTime;

/**
 * 호가창 row 클릭 시 하단 시트에 표시되는 등록자 한 명.
 *
 * @param userId       등록자 user_id
 * @param nickname     닉네임 (User join, null 가능)
 * @param price        등록 가격
 * @param memo         메모 (null 가능)
 * @param createdAt    등록 시각
 * @param assetId      TradePost 의 asset_id (ASK 만). BID 는 null
 * @param tradeId      TradePost id (ASK 만). BID 는 null
 * @param buyOrderId   BuyOrder id (BID 만). ASK 는 null
 */
public record HogaListingResponse(
        String userId,
        String nickname,
        long price,
        String memo,
        LocalDateTime createdAt,
        String assetId,
        String tradeId,
        String buyOrderId) {}
