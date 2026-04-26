package com.fury.back.domain.trade;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface TradePostRepository extends JpaRepository<TradePost, String> {

    Page<TradePost> findByStatusOrderByCreatedAtDesc(String status, Pageable pageable);

    Page<TradePost> findBySellerIdOrderByCreatedAtDesc(String sellerId, Pageable pageable);

    @Query("SELECT t FROM TradePost t WHERE t.status = 'OPEN' AND " +
           "(:cardId IS NULL OR t.cardId = :cardId) " +
           "ORDER BY t.createdAt DESC")
    Page<TradePost> findOpenByCardId(@Param("cardId") String cardId, Pageable pageable);

    List<TradePost> findBySellerIdAndStatus(String sellerId, String status);

    // 카드별 그룹 요약: cardId, 판매 수, 평균가, 최저가
    @Query("SELECT t.cardId, COUNT(t), AVG(t.price), MIN(t.price) " +
           "FROM TradePost t WHERE t.status = 'OPEN' AND t.price IS NOT NULL " +
           "GROUP BY t.cardId ORDER BY COUNT(t) DESC")
    List<Object[]> findCardTradeSummary(Pageable pageable);
}
