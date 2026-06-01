package com.fury.back.domain.interest;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface PostInterestRepository extends JpaRepository<PostInterest, String> {

    Optional<PostInterest> findByUserIdAndTradeId(String userId, String tradeId);

    boolean existsByUserIdAndTradeId(String userId, String tradeId);

    List<PostInterest> findByUserIdOrderByCreatedAtDesc(String userId);

    void deleteByUserIdAndTradeId(String userId, String tradeId);

    /** 거래 list 판매글별 batch count — N+1 방지. 각 row = [tradeId, count]. */
    @Query("SELECT pi.tradeId, COUNT(pi) FROM PostInterest pi WHERE pi.tradeId IN :tradeIds GROUP BY pi.tradeId")
    List<Object[]> countByTradeIdIn(@Param("tradeIds") List<String> tradeIds);

    /** 단건 — 거래 상세 favoriteCount용. */
    long countByTradeId(String tradeId);
}
