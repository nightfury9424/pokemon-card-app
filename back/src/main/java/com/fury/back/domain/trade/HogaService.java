package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaBoardResponse;
import com.fury.back.domain.trade.dto.HogaListingsResponse;

public interface HogaService {

    /** 카드별 호가창 (매도/매수 5행씩). */
    HogaBoardResponse getBoard(String cardId, HogaStatus status, int limit);

    /** 특정 가격에 등록된 매도/매수 리스트. */
    HogaListingsResponse getListingsAtPrice(String cardId, HogaStatus status, HogaSide side, long price);
}
