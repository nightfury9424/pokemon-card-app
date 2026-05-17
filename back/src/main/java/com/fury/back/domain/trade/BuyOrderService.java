package com.fury.back.domain.trade;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.trade.dto.BuyOrderDto;
import org.springframework.data.domain.Page;

import java.util.List;

public interface BuyOrderService {
    /** 카드별 매수 호가 (호가창용, OPEN, bid 높은 순) */
    ReturnData<List<BuyOrderDto>> getByCard(String cardId);

    /** 페이징 카드별 호가 */
    ReturnData<Page<BuyOrderDto>> getByCardPaged(String cardId, int page, int size);

    /** 내 매수 주문 list */
    ReturnData<List<BuyOrderDto>> getMyOrders(String buyerId, String status);

    /** 전체 OPEN 매수 호가 페이징 (거래 탭 매수 list용) */
    ReturnData<Page<BuyOrderDto>> getAllOpen(int page, int size);

    /** 매수 호가 등록 */
    ReturnData<BuyOrderDto> create(String buyerId, ParameterData params);

    /** 가격 수정 */
    ReturnData<BuyOrderDto> updateBidPrice(String buyOrderId, String buyerId, Integer newPrice);

    /** 취소 (status → CANCELED) */
    ReturnData<Void> cancel(String buyOrderId, String buyerId);

    /** 체결 표시 (status → MATCHED, matched_trade_id 연결) */
    ReturnData<BuyOrderDto> markMatched(String buyOrderId, String buyerId, String tradeId);
}
