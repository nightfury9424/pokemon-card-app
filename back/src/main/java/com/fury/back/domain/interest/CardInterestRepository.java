package com.fury.back.domain.interest;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Set;

public interface CardInterestRepository extends JpaRepository<CardInterest, String> {

    boolean existsByUserIdAndCardId(String userId, String cardId);

    List<CardInterest> findByUserIdOrderByCreatedAtDesc(String userId);

    /** 거래 리스트 row마다 isLiked 표시 — 배치 조회용. */
    List<CardInterest> findByUserIdAndCardIdIn(String userId, Collection<String> cardIds);

    void deleteByUserIdAndCardId(String userId, String cardId);
}
