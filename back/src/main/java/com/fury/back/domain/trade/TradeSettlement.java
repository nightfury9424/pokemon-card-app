package com.fury.back.domain.trade;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 실거래가 수집 — 거래 완료 후 양쪽 당사자(판매자 + 매칭된 buyer)가 실제 거래 금액을 기입.
 * (trade_id, user_id) UNIQUE. APP_TRADE 시세 소스의 원천 데이터.
 *
 * <p>정책 (2026-06-04): 수집 단계는 <b>저장만</b> 한다. 시세 반영(APP_TRADE 스냅샷 생성)은
 * 후속 '마지막 리터치'에서 일일 시세 동기화 배치가 outlier 자동 필터 후 처리한다.
 * 여기서 v6 가격 모델은 건드리지 않는다 (freeze 보호).
 */
@Entity
@Table(name = "trade_settlements")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class TradeSettlement {

    @Id
    @Column(name = "settlement_id", length = 50)
    private String settlementId;

    @Column(name = "trade_id", nullable = false, length = 50)
    private String tradeId;

    /** 입력한 유저 (판매자 or 매칭 buyer). */
    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    /** SELLER / BUYER. */
    @Column(name = "role", nullable = false, length = 10)
    private String role;

    /** 시세 소스 매핑용 denormalize. */
    @Column(name = "card_id", length = 50)
    private String cardId;

    @Column(name = "reported_price", nullable = false)
    private Integer reportedPrice;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    /** 재입력(수정) 시 값 갱신. */
    public void updatePrice(Integer price) {
        this.reportedPrice = price;
        this.updatedAt = LocalDateTime.now();
    }

    @PrePersist
    void prePersist() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
