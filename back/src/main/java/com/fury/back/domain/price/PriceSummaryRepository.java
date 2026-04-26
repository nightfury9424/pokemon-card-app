package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PriceSummaryRepository extends JpaRepository<PriceSummary, String> {
    List<PriceSummary> findByCardId(String cardId);

    Optional<PriceSummary> findByCardIdAndCardStatusAndPeriod(String cardId, String cardStatus, String period);
}
