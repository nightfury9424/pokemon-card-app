package com.fury.back.domain.trade;

import org.springframework.data.jpa.repository.JpaRepository;

public interface TradePostViewRepository extends JpaRepository<TradePostView, String> {

    boolean existsByTradeIdAndUserId(String tradeId, String userId);
}
