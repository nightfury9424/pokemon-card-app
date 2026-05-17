package com.fury.back.domain.user;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "users")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class User {

    @Id
    @Column(name = "user_id", length = 50)
    private String userId;

    @Column(name = "google_id", nullable = false, unique = true, length = 100)
    private String googleId;

    @Column(name = "nickname", length = 50)
    private String nickname;

    @Column(name = "email", length = 200)
    private String email;

    @Column(name = "profile_image_url", length = 500)
    private String profileImageUrl;

    @Column(name = "onboarded", nullable = false)
    private boolean onboarded;

    @Column(name = "nickname_changed_at")
    private LocalDateTime nicknameChangedAt;

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
}
