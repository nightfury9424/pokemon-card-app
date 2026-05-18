package com.fury.back.domain.trade;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 매수 호가 ("삽니다"). 판매 호가(TradePost)와 양방향 호가창 구성.
 * 채팅 기반 협상 — 자동 매칭 X. 4차-Round4-4 Phase 1.
 *
 * 제약:
 * - 동일 사용자 + 동일 카드 + OPEN = 1개만 (DB unique index)
 * - 한 사용자 OPEN 총 5개 한도 (Service level)
 * - 무기한 (만료 없음)
 * - 매수자는 사진 X (단순 가격 + 카드 + 조건)
 */
@Entity
@Table(name = "buy_orders")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class BuyOrder {

    @Id
    @Column(name = "buy_order_id", length = 50)
    private String buyOrderId;

    @Column(name = "buyer_id", nullable = false, length = 50)
    private String buyerId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    @Column(name = "bid_price", nullable = false)
    private Integer bidPrice;

    @Column(name = "qty", nullable = false)
    private Integer qty;

    /** RAW / GRADED — TradePost와 동일 */
    @Column(name = "card_status", nullable = false, length = 20)
    private String cardStatus;

    /** PSA / BRG — GRADED일 때만 (CGC/BGS 미지원) */
    @Column(name = "grading_company", length = 20)
    private String gradingCompany;

    /** 10 / 9.5 / ... — GRADED일 때만 */
    @Column(name = "grade_value", length = 20)
    private String gradeValue;

    @Column(name = "memo", columnDefinition = "TEXT")
    private String memo;

    /** OPEN / MATCHED / CANCELED */
    @Column(name = "status", nullable = false, length = 20)
    private String status;

    /** 체결 시 연결된 거래 ID (선택) */
    @Column(name = "matched_trade_id", length = 50)
    private String matchedTradeId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
        if (this.status == null) this.status = "OPEN";
        if (this.qty == null) this.qty = 1;
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    public void updateStatus(String newStatus) {
        this.status = newStatus;
    }

    public void updateBidPrice(Integer newPrice) {
        this.bidPrice = newPrice;
    }

    public void updateMatchedTradeId(String tradeId) {
        this.matchedTradeId = tradeId;
    }
}
