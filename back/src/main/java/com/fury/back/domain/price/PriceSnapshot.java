package com.fury.back.domain.price;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "price_snapshots")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PriceSnapshot {

    @Id
    @Column(name = "price_snapshot_id", length = 50)
    private String priceSnapshotId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    // NAVER_CAFE / BUNJANG / SCRYDEX_EN / SCRYDEX_JP / KO_ESTIMATED
    @Column(name = "source", nullable = false, length = 20)
    private String source;

    @Column(name = "source_item_id", length = 100)
    private String sourceItemId;

    @Column(name = "source_url", length = 500)
    private String sourceUrl;

    @Column(name = "title", length = 500)
    private String title;

    @Column(name = "price", nullable = false)
    private Integer price;

    @Column(name = "raw_price")
    private BigDecimal rawPrice;

    @Column(name = "raw_currency", length = 3)
    private String rawCurrency;

    // RAW / GRADED
    @Column(name = "card_status", nullable = false, length = 20)
    private String cardStatus;

    // PSA / BRG
    @Column(name = "grading_company", length = 20)
    private String gradingCompany;

    // 10 / 9.5 ...
    @Column(name = "grade_value", length = 20)
    private String gradeValue;

    @Column(name = "cert_number", length = 100)
    private String certNumber;

    @Column(name = "traded_at", nullable = false)
    private LocalDateTime tradedAt;

    @Column(name = "collected_at", nullable = false)
    private LocalDateTime collectedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
