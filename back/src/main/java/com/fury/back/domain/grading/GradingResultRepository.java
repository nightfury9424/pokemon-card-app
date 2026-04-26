package com.fury.back.domain.grading;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface GradingResultRepository extends JpaRepository<GradingResult, String> {
    List<GradingResult> findByUserIdOrderByCreatedAtDesc(String userId);
}
