package com.fury.back.domain.asset;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

@Entity
@Table(name = "assets")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Asset {

    @Id
    @Column(name = "asset_id", length = 50)
    private String assetId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    @Column(name = "quantity", nullable = false)
    private Integer quantity;

    @Column(name = "purchase_price")
    private Integer purchasePrice;

    // KO / JP / EN
    @Column(name = "language", length = 10)
    private String language;

    // RAW / GRADED
    @Column(name = "card_status", nullable = false, length = 20)
    private String cardStatus;

    // PSA / BRG
    @Column(name = "grading_company", length = 20)
    private String gradingCompany;

    @Column(name = "grade_value", length = 20)
    private String gradeValue;

    @Column(name = "cert_number", length = 100)
    private String certNumber;

    @Column(name = "estimated_grade", precision = 3, scale = 1)
    private BigDecimal estimatedGrade;

    @Column(name = "centering_score", precision = 3, scale = 1)
    private BigDecimal centeringScore;

    @Column(name = "corner_score", precision = 3, scale = 1)
    private BigDecimal cornerScore;

    @Column(name = "surface_score", precision = 3, scale = 1)
    private BigDecimal surfaceScore;

    @Column(name = "whitening_score", precision = 3, scale = 1)
    private BigDecimal whiteningScore;

    @Column(name = "centering_ratio", length = 50)
    private String centeringRatio;

    @Column(name = "detection_confidence", precision = 3, scale = 2)
    private BigDecimal detectionConfidence;

    @Column(name = "grading_analyzed_at")
    private LocalDateTime gradingAnalyzedAt;

    @Column(name = "memo", columnDefinition = "TEXT")
    private String memo;

    @Column(name = "purchased_at")
    private LocalDate purchasedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    public void update(Integer quantity, Integer purchasePrice, String memo, LocalDate purchasedAt) {
        this.quantity = quantity;
        this.purchasePrice = purchasePrice;
        this.memo = memo;
        this.purchasedAt = purchasedAt;
    }

    public void updateGradingResult(
            BigDecimal estimatedGrade,
            BigDecimal centeringScore,
            BigDecimal cornerScore,
            BigDecimal surfaceScore,
            BigDecimal whiteningScore,
            String centeringRatio,
            BigDecimal detectionConfidence
    ) {
        this.estimatedGrade = estimatedGrade;
        this.centeringScore = centeringScore;
        this.cornerScore = cornerScore;
        this.surfaceScore = surfaceScore;
        this.whiteningScore = whiteningScore;
        this.centeringRatio = centeringRatio;
        this.detectionConfidence = detectionConfidence;
        this.gradingAnalyzedAt = LocalDateTime.now();
    }

    public void updateCertNumberIfEmpty(String certNumber) {
        if ((this.certNumber == null || this.certNumber.isBlank()) && certNumber != null && !certNumber.isBlank()) {
            this.certNumber = certNumber;
        }
    }

    public void setGradingCompany(String gradingCompany) {
        this.gradingCompany = gradingCompany;
    }

    public void setGradeValue(String gradeValue) {
        this.gradeValue = gradeValue;
    }
}
