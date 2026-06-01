package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaBoardResponse;
import com.fury.back.domain.trade.dto.HogaListingsResponse;

public interface HogaService {

    /**
     * 카드별 호가창 (매도/매수 5행씩). grade는 PSA/BRG일 때만 의미 있음 ("10" / "9").
     * viewerUserId 가 null 이 아니면 각 level 에 hasMine 플래그 채움 (Phase 4 MY badge).
     */
    HogaBoardResponse getBoard(String cardId, HogaStatus status, String grade, int limit, String viewerUserId);

    /** 특정 가격에 등록된 매도/매수 리스트. */
    HogaListingsResponse getListingsAtPrice(
            String cardId, HogaStatus status, String grade, HogaSide side, long price);
}
