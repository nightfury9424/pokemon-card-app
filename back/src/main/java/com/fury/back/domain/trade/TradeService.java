package com.fury.back.domain.trade;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.trade.dto.TradePostDto;
import org.springframework.data.domain.Page;

public interface TradeService {

    /**
     * Phase 1: sellerId+cardId 동시 필터 + status optional 지원.
     * status 미지정(null) 시 기존 동작(전체) 호환.
     */
    ReturnData<Page<TradePostDto>> getTrades(int page, int size, String cardId, String sellerId, String status, String viewerUserId);

    /** viewerUserId 받아서 1인 1조회 카운트 + chatCount/favoriteCount 매핑. */
    ReturnData<TradePostDto> getTrade(String tradeId, String viewerUserId);

    ReturnData<TradePostDto> createTrade(String sellerId, ParameterData parameterData);

    ReturnData<TradePostDto> createTradeFromAsset(String sellerId, ParameterData parameterData);

    ReturnData<TradePostDto> updateTrade(String tradeId, String userId, ParameterData parameterData);

    ReturnData<Void> deleteTrade(String tradeId, String userId);

    ReturnData<TradePostDto> updateStatus(String tradeId, String userId, String status);

    ReturnData<String> uploadImage(String tradeId, String userId, org.springframework.web.multipart.MultipartFile file);

    ReturnData<java.util.List<java.util.Map<String, Object>>> getCardTradeSummaries(int size);
}
