package com.fury.back.domain.trade;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "trade_posts")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class TradePost {

    @Id
    @Column(name = "trade_id", length = 50)
    private String tradeId;

    @Column(name = "seller_id", nullable = false, length = 50)
    private String sellerId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    @Column(name = "asset_id", length = 50)
    private String assetId;

    @Column(name = "title", nullable = false, length = 200)
    private String title;

    @Column(name = "description", columnDefinition = "TEXT")
    private String description;

    // null = 가격 협의
    @Column(name = "price")
    private Integer price;

    // RAW / GRADED
    @Column(name = "card_status", nullable = false, length = 20)
    private String cardStatus;

    @Column(name = "grading_company", length = 20)
    private String gradingCompany;

    @Column(name = "grade_value", length = 20)
    private String gradeValue;

    // 최상 / 상 / 중 / 중하 / 하
    @Column(name = "condition", length = 20)
    private String condition;

    @Column(name = "cert_number", length = 50)
    private String certNumber;

    @Column(name = "image_url", columnDefinition = "TEXT")
    private String imageUrl;

    // OPEN / RESERVED / SOLD
    @Column(name = "status", nullable = false, length = 20)
    @Builder.Default
    private String status = "OPEN";

    @Column(name = "view_count", nullable = false)
    @Builder.Default
    private Integer viewCount = 0;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    // Bundle 2-A.7 (2026-05-22): soft delete 추적. status='DELETED'와 짝으로 set.
    // 분쟁/감사용 타임스탬프. NULL = 활성, NOT NULL = 삭제됨.
    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    public void update(String title, String description, Integer price) {
        this.title = title;
        this.description = description;
        this.price = price;
    }

    public void updateImageUrl(String imageUrl) {
        this.imageUrl = imageUrl;
    }

    public void updateCondition(String condition) {
        this.condition = condition;
    }

    public void updateStatus(String status) {
        this.status = status;
    }

    public void incrementViewCount() {
        this.viewCount++;
    }

    /**
     * Bundle 2-A.7: soft delete — status='DELETED' + deletedAt=now.
     * 기존 hard delete (tradePostRepository.delete) 대체.
     * 채팅방은 status 무관 메시지/미니카드 유지 — 분쟁/신고 근거 보존.
     */
    public void markDeleted() {
        this.status = "DELETED";
        this.deletedAt = LocalDateTime.now();
    }
}
