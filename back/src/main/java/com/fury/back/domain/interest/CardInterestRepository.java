package com.fury.back.domain.interest;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;
import java.util.Set;

public interface CardInterestRepository extends JpaRepository<CardInterest, String> {

    boolean existsByUserIdAndCardId(String userId, String cardId);

    List<CardInterest> findByUserIdOrderByCreatedAtDesc(String userId);

    /** 거래 리스트 row마다 isLiked 표시 — 배치 조회용. */
    List<CardInterest> findByUserIdAndCardIdIn(String userId, Collection<String> cardIds);

    /**
     * 거래 리스트 row engagement 카운트 (Phase 1) — 카드별 관심(찜) 총 수 batch.
     * 결과: List<Object[]> = (cardId, count). 빈 카드는 결과에 없음(0으로 처리).
     */
    @Query("SELECT i.cardId, COUNT(i) FROM CardInterest i WHERE i.cardId IN :cardIds GROUP BY i.cardId")
    List<Object[]> countByCardIds(@Param("cardIds") Collection<String> cardIds);

    void deleteByUserIdAndCardId(String userId, String cardId);
}
