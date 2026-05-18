package com.fury.back.domain.trade.dto;

import java.util.List;

/**
 * 호가 row(특정 가격) 클릭 시 등록자 리스트 응답.
 */
public record HogaListingsResponse(
        String cardId,
        String status,
        String side,
        long price,
        int totalCount,
        List<HogaListingResponse> listings) {}
