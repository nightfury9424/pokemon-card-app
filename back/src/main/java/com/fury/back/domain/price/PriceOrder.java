package com.fury.back.domain.price;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "price_orders")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PriceOrder {

    @Id
    @Column(name = "order_id", length = 50)
    private String orderId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    // BUY / SELL
    @Column(name = "order_type", nullable = false, length = 10)
    private String orderType;

    @Column(name = "price", nullable = false)
    private Integer price;

    // OPEN / CANCELLED
    @Column(name = "status", nullable = false, length = 20)
    @Builder.Default
    private String status = "OPEN";

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

    public void cancel() {
        this.status = "CANCELLED";
    }
}
