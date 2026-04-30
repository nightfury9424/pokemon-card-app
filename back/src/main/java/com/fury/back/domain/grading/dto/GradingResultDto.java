package com.fury.back.domain.grading.dto;

import lombok.Builder;
import lombok.Data;
import java.math.BigDecimal;

@Data @Builder
public class GradingResultDto {
    private BigDecimal centeringScore;
    private BigDecimal cornerScore;
    private BigDecimal surfaceScore;
    private BigDecimal whiteningScore;
    private BigDecimal totalScore;
    private boolean heavyWhitening;
    private String centeringDetail;
    private String cornerDetail;
    private String surfaceDetail;
    private String whiteningDetail;
}
