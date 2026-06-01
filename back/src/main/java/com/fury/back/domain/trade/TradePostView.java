package com.fury.back.domain.trade;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * 판매글 조회 기록. (trade_id, user_id) UNIQUE — 1인 1조회 정책.
 * 판매자 본인 조회는 backend에서 INSERT 자체를 skip.
 */
@Entity
@Table(
        name = "trade_post_views",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_trade_post_views_trade_user",
                columnNames = {"trade_id", "user_id"}))
@Getter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class TradePostView {

    @Id
    @Column(name = "view_id")
    private String viewId;

    @Column(name = "trade_id", nullable = false)
    private String tradeId;

    @Column(name = "user_id", nullable = false)
    private String userId;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        if (this.createdAt == null) this.createdAt = LocalDateTime.now();
    }
}
