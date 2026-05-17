package com.fury.back.domain.trade;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface BuyOrderRepository extends JpaRepository<BuyOrder, String> {

    /** 카드별 OPEN 매수 호가 — bid 높은 순 (호가창용) */
    @Query("SELECT bo FROM BuyOrder bo WHERE bo.cardId = :cardId AND bo.status = 'OPEN' ORDER BY bo.bidPrice DESC, bo.createdAt ASC")
    List<BuyOrder> findOpenByCardIdOrderByBidPriceDesc(@Param("cardId") String cardId);

    /** 사용자 OPEN 매수 호가 (5개 한도 체크 + 내 주문 목록) */
    List<BuyOrder> findByBuyerIdAndStatusOrderByCreatedAtDesc(String buyerId, String status);

    /** 동일 사용자 + 동일 카드 + OPEN 존재 여부 (1개만 제약) */
    Optional<BuyOrder> findFirstByBuyerIdAndCardIdAndStatus(String buyerId, String cardId, String status);

    /** 페이징 — 카드별 호가 list */
    @Query("SELECT bo FROM BuyOrder bo WHERE bo.cardId = :cardId AND bo.status = 'OPEN' ORDER BY bo.bidPrice DESC, bo.createdAt ASC")
    Page<BuyOrder> findOpenPageByCardId(@Param("cardId") String cardId, Pageable pageable);

    /** 사용자 OPEN 개수 (5개 한도 체크용) */
    long countByBuyerIdAndStatus(String buyerId, String status);

    /** 전체 OPEN 매수 호가 페이징 (거래 탭 매수 list용) — bid 높은 순 */
    Page<BuyOrder> findByStatusOrderByBidPriceDescCreatedAtDesc(String status, Pageable pageable);
}
