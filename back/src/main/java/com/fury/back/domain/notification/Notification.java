package com.fury.back.domain.notification;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "notifications")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Notification {

    @Id
    @Column(name = "notification_id", length = 50)
    private String notificationId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    /** BUY_ORDER_ON_MY_CARD / TRADE_ON_MY_BUY_ORDER / ... */
    @Column(name = "type", nullable = false, length = 40)
    private String type;

    @Column(name = "title", nullable = false, length = 120)
    private String title;

    @Column(name = "body", columnDefinition = "TEXT")
    private String body;

    @Column(name = "link_card_id", length = 50)
    private String linkCardId;

    @Column(name = "link_url", length = 255)
    private String linkUrl;

    @Column(name = "is_read", nullable = false)
    private Boolean isRead;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (this.createdAt == null) this.createdAt = LocalDateTime.now();
        if (this.isRead == null) this.isRead = false;
    }

    public void markRead() {
        this.isRead = true;
    }
}
