package com.fury.back.domain.grading.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;
import java.math.BigDecimal;

@Data
public class GradingAnalysisDto {
    @JsonProperty("centering_score")  private BigDecimal centeringScore;
    @JsonProperty("corner_score")     private BigDecimal cornerScore;
    @JsonProperty("surface_score")    private BigDecimal surfaceScore;
    @JsonProperty("whitening_score")  private BigDecimal whiteningScore;
    @JsonProperty("total_score")      private BigDecimal totalScore;
    @JsonProperty("heavy_whitening")  private boolean heavyWhitening;
    @JsonProperty("centering_ratio")       private String centeringRatio;
    @JsonProperty("detection_confidence") private Double detectionConfidence;
    @JsonProperty("centering_detail") private String centeringDetail;
    @JsonProperty("corner_detail")    private String cornerDetail;
    @JsonProperty("surface_detail")   private String surfaceDetail;
    @JsonProperty("whitening_detail") private String whiteningDetail;
    @JsonProperty("identity_verified") private boolean identityVerified;
}
