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

    /**
     * 계정 탈퇴 시각 (soft delete). null = 활성. App Review 5.1.1 대응.
     * deletedAt != null 인 계정은 DeletedUserGuardFilter에서 401 차단.
     */
    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    // ─────────────────────────────────────────────────────────────────────
    // 2026-05-29 admin Stage 0 (Codex C) — 사용자 정지/복구.
    //   suspended_at NOT NULL = 정지 중 → DeletedUserGuardFilter 가 USER_SUSPENDED 별도 코드로 차단.
    //   복구 시 suspended_at NULL + unsuspended_at = now (감사 trail).
    //   PII 마스킹 X (deleted_at 와 다름) — 복구 시 정보 그대로.
    // ─────────────────────────────────────────────────────────────────────

    @Column(name = "suspended_at")
    private LocalDateTime suspendedAt;

    @Column(name = "suspension_reason", columnDefinition = "TEXT")
    private String suspensionReason;

    @Column(name = "suspended_by", length = 50)
    private String suspendedBy;

    @Column(name = "unsuspended_at")
    private LocalDateTime unsuspendedAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    /** 2026-05-29: 정지 처리. AdminUserService 에서 호출. */
    public void suspend(String reason, String adminUserId) {
        this.suspendedAt = LocalDateTime.now();
        this.suspensionReason = reason;
        this.suspendedBy = adminUserId;
        this.unsuspendedAt = null;
    }

    /** 2026-05-29: 정지 해제. PII 마스킹 안 풀음 (정지 != 탈퇴). */
    public void unsuspend() {
        this.suspendedAt = null;
        this.unsuspendedAt = LocalDateTime.now();
        // suspensionReason / suspendedBy 는 audit 용 유지.
    }

    /** 정지 상태 여부. */
    public boolean isSuspended() {
        return this.suspendedAt != null;
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }

    /**
     * 탈퇴 처리: PII(nickname/email/profileImageUrl) 마스킹 + deletedAt 설정.
     * googleId는 유지 — 같은 Google 계정으로 재로그인 시 "탈퇴한 계정" 감지 위함.
     * 거래/채팅/신고/차단 데이터는 FK 무결성 + 분쟁 증거 보존 위해 별도 보존 (UserService에서 처리).
     */
    public void markDeletedAndMask(String maskedNickname) {
        this.nickname = maskedNickname;
        this.email = null;
        this.profileImageUrl = null;
        this.deletedAt = LocalDateTime.now();
    }
}
