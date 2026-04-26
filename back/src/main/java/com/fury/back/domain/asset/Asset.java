package com.fury.back.domain.asset;

import jakarta.persistence.*;
import lombok.*;

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

    // RAW / GRADED
    @Column(name = "card_status", nullable = false, length = 20)
    private String cardStatus;

    // PSA / BGS / CGC / OTHER
    @Column(name = "grading_company", length = 20)
    private String gradingCompany;

    @Column(name = "grade_value", length = 20)
    private String gradeValue;

    @Column(name = "cert_number", length = 100)
    private String certNumber;

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
}
