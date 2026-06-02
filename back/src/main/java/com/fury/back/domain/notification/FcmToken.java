package com.fury.back.domain.notification;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * FCM 기기 푸시 토큰. 사용자당 여러 기기 가능. token unique — 기기 재로그인 시 userId relink.
 * in-app Notification(notifications 테이블)과 별개 — 이건 "기기 전송" 채널용.
 */
@Entity
@Table(name = "fcm_tokens")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class FcmToken {

    @Id
    @Column(name = "token_id", length = 50)
    private String tokenId;

    @Column(name = "user_id", length = 50, nullable = false)
    private String userId;

    @Column(name = "token", length = 500, nullable = false, unique = true)
    private String token;

    @Column(name = "platform", length = 20)
    private String platform;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    /** 같은 토큰이 다른 계정으로 재로그인 시 소유자/플랫폼 갱신. */
    public void relink(String userId, String platform) {
        this.userId = userId;
        this.platform = platform;
    }
}
