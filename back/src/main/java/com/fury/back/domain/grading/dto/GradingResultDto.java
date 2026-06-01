package com.fury.back.domain.grading.dto;

import lombok.Builder;
import lombok.Data;

import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@Data
@Builder
public class GradingResultDto {
    private BigDecimal centeringScore;
    private BigDecimal cornerScore;
    private BigDecimal surfaceScore;
    private BigDecimal whiteningScore;
    private BigDecimal totalScore;
    private boolean heavyWhitening;
    private String centeringRatio;
    private Double detectionConfidence;
    private String centeringDetail;
    private String cornerDetail;
    private String surfaceDetail;
    private String whiteningDetail;
    private boolean identityVerified;

    private BigDecimal edgeScore;
    private String edgeDetail;
    private BigDecimal weightedScore;
    private BigDecimal totalScoreDisplay;
    private String grade;
    private String gradeColor;
    private List<DeductionReasonDto> deductionReasons;
    private List<DefectRegionDto> defectRegions;
    private boolean hasMajorDefect;
    private boolean retakeRequired;
    private String retakeReason;
    private String captureQuality;

    private boolean screenSuspected;
    private String screenSuspectReason;

    // === P0-1 evidence layer (Phase 2-C) ===
    // P0-fix-1: cardBbox / cornerRegions 가 front + back nested (back overlay mismatch fix).
    private Map<String, Object> cardBbox;
    private Map<String, Double> centeringLines;
    private Double centeringConfidence;
    private String centeringSource;
    private Map<String, Object> cornerRegions;
    private Map<String, Object> gradeDecisionTrace;
    private Map<String, Object> extra;
}
