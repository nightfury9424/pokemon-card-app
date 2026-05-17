package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PriceOrderRepository extends JpaRepository<PriceOrder, String> {
    List<PriceOrder> findByCardIdAndStatusOrderByPriceDesc(String cardId, String status);
    List<PriceOrder> findByCardIdAndStatusOrderByPriceAsc(String cardId, String status);
    List<PriceOrder> findByCardIdAndUserIdAndStatus(String cardId, String userId, String status);
}
