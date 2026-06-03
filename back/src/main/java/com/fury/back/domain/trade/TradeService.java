package com.fury.back.domain.trade;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.trade.dto.ChatPartnerDto;
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

    /**
     * 거래중 모델: status 변경 + (RESERVED 시) activeChatRoomId 지정.
     * - RESERVED + chatRoomId NOT NULL → activeChatRoomId set
     * - RESERVED + chatRoomId NULL → 기존 호환 (active 변경 X, backfill 안 한 데이터 보호)
     * - OPEN → activeChatRoomId NULL clear
     * - COMPLETED / DELETED → activeChatRoomId 그대로 (선택 상대 후속 대화 가능 정책)
     */
    ReturnData<TradePostDto> updateStatus(String tradeId, String userId, String status, String chatRoomId);

    /** 실거래가 입력 상태 — 완료 모달/소프트 인터셉터 노출 판단 + prefill. */
    ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> getSettlementStatus(String tradeId, String userId);

    /** 실거래가 입력(수집만, 시세 반영은 후속 배치). 당사자 + COMPLETED 만. (trade,user) upsert. */
    ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> submitSettlement(String tradeId, String userId, Integer price);

    /** B2-12: 구매(BuyOrder) 실거래가 — SALE 대칭. trade_settlements 에 trade_id=buyOrderId 저장. */
    ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> getBuySettlementStatus(String buyOrderId, String userId);
    ReturnData<com.fury.back.domain.trade.dto.TradeSettlementStatusDto> submitBuySettlement(String buyOrderId, String userId, Integer price);

    /**
     * 거래중 모델: 판매글에 연결된 채팅 상대 list (거래중 변경 시 상대 선택용).
     * 판매자만 호출 가능. 차단 user 는 제외 — backend 가 후보 확정.
     */
    ReturnData<java.util.List<ChatPartnerDto>> getChatPartners(String tradeId, String userId);

    /**
     * MY > 내 판매 내역 — 본인의 OPEN/RESERVED/COMPLETED 판매글 이력.
     * DELETED 숨김. 공개 거래 목록/호가/MY 상단 카운트와 분리된 별도 history view.
     * IDOR 방지 — sellerId 는 JWT 인증 principal 기준, request param 으로 받지 않음.
     */
    ReturnData<Page<TradePostDto>> getMyHistory(String sellerId, int page, int size);

    ReturnData<String> uploadImage(String tradeId, String userId, org.springframework.web.multipart.MultipartFile file);

    ReturnData<java.util.List<java.util.Map<String, Object>>> getCardTradeSummaries(int size);
}
