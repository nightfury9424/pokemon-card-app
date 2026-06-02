package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaBoardResponse;
import com.fury.back.domain.trade.dto.HogaListingsResponse;

public interface HogaService {

    /**
     * 카드별 호가창 (매도/매수 5행씩). grade는 PSA/BRG일 때만 의미 있음 ("10" / "9").
     * viewerUserId 가 null 이 아니면 각 level 에 hasMine 플래그 채움 (Phase 4 MY badge).
     */
    HogaBoardResponse getBoard(String cardId, HogaStatus status, String grade, int limit, String viewerUserId);

    /** 특정 가격에 등록된 매도/매수 리스트. viewerUserId 가 차단한 사용자 호가는 제외. */
    HogaListingsResponse getListingsAtPrice(
            String cardId, HogaStatus status, String grade, HogaSide side, long price, String viewerUserId);

    /**
     * 전 가격에 걸쳐 매도/매수 top-N (주문 전 매칭 시트용).
     * ASK=낮은가 먼저, BID=높은가 먼저. price 필드는 미사용(0) — 각 listing 의 자체 price 사용.
     * viewerUserId 가 차단한 사용자 호가는 제외.
     */
    HogaListingsResponse getTopListings(
            String cardId, HogaStatus status, String grade, HogaSide side, int limit, String viewerUserId);
}
