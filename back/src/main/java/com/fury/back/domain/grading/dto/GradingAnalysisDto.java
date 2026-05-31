package com.fury.back.domain.grading.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.math.BigDecimal;
import java.util.List;

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

    @JsonProperty("edge_score")          private BigDecimal edgeScore;
    @JsonProperty("edge_detail")         private String edgeDetail;
    @JsonProperty("weighted_score")      private BigDecimal weightedScore;
    @JsonProperty("total_score_display") private BigDecimal totalScoreDisplay;
    @JsonProperty("grade")               private String grade;
    @JsonProperty("grade_color")         private String gradeColor;
    @JsonProperty("deduction_reasons")   private List<DeductionReasonDto> deductionReasons;
    @JsonProperty("defect_regions")      private List<DefectRegionDto> defectRegions;
    @JsonProperty("has_major_defect")    private boolean hasMajorDefect;
    @JsonProperty("retake_required")     private boolean retakeRequired;
    @JsonProperty("retake_reason")       private String retakeReason;
    @JsonProperty("capture_quality")     private String captureQuality;

    @JsonProperty("screen_suspected")      private boolean screenSuspected;
    @JsonProperty("screen_suspect_reason") private String screenSuspectReason;
}
