package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;

public interface CardMarketSegmentOverrideRepository
        extends JpaRepository<CardMarketSegmentOverride, String> {

    /** batch fetch — per-card query 금지 정책 (사용자 spec). */
    List<CardMarketSegmentOverride> findByCardIdIn(Collection<String> cardIds);
}
