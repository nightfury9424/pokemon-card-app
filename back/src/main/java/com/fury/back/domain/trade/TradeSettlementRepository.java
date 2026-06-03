package com.fury.back.domain.trade;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface TradeSettlementRepository extends JpaRepository<TradeSettlement, String> {
    Optional<TradeSettlement> findByTradeIdAndUserId(String tradeId, String userId);
    boolean existsByTradeIdAndUserId(String tradeId, String userId);
}
