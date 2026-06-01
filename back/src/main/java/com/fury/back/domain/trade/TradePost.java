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

    /**
     * 거래중("RESERVED") 상태 시 선택된 채팅방 id. 선택된 buyer 와 판매자만 채팅 가능,
     * 나머지 buyer 는 isExcludedFromActiveTrade=true 로 입력 비활성.
     * - RESERVED + NOT NULL: 거래중 + 상대 지정
     * - RESERVED + NULL: 기존 데이터 (backfill X) — 거래중 상대 미지정
     * - OPEN 복귀 시 clear
     * - COMPLETED: 유지 (후속 대화 가능)
     */
    @Column(name = "active_chat_room_id", length = 50)
    private String activeChatRoomId;

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

    /** 거래중 상대 지정 — RESERVED 상태 변경 시 active_chat_room_id set. */
    public void setActiveChatRoom(String chatRoomId) {
        this.activeChatRoomId = chatRoomId;
    }

    /** OPEN 복귀 시 active_chat_room_id NULL clear — 모든 상대 다시 채팅 가능. */
    public void clearActiveChatRoom() {
        this.activeChatRoomId = null;
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
