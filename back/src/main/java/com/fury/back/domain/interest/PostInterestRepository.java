package com.fury.back.domain.interest;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface PostInterestRepository extends JpaRepository<PostInterest, String> {

    Optional<PostInterest> findByUserIdAndTradeId(String userId, String tradeId);

    boolean existsByUserIdAndTradeId(String userId, String tradeId);

    List<PostInterest> findByUserIdOrderByCreatedAtDesc(String userId);

    void deleteByUserIdAndTradeId(String userId, String tradeId);
}
