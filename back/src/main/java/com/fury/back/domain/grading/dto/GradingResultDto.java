package com.fury.back.domain.grading.dto;

import lombok.Builder;
import lombok.Data;
import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data @Builder
public class GradingResultDto {
    private String resultId;
    private String cardId;
    private BigDecimal centeringScore;
    private BigDecimal cornerScore;
    private BigDecimal surfaceScore;
    private BigDecimal whiteningScore;
    private BigDecimal totalScore;
    private boolean heavyWhitening;
    private LocalDateTime createdAt;
}
