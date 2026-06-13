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

    // Apple 로그인 추가로 nullable — Google/Apple 중 하나로 가입.
    @Column(name = "google_id", unique = true, length = 100)
    private String googleId;

    /** Sign in with Apple sub (고유 id). Google 미사용 가입 시 사용. */
    @Column(name = "apple_id", unique = true, length = 100)
    private String appleId;

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

    /** 마지막 활동 시각 — 인증 요청 시 throttled(60s) 갱신. DAU(오늘 접속)/접속중 집계용. nullable(아직 활동 없는 유저). */
    @Column(name = "last_seen_at")
    private LocalDateTime lastSeenAt;

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

    // ── 2026-06-02 만 14세 self-declared 게이트 (한국 PIPA). 생년월일 미저장 — 확인값만. ──
    /** 만 14세 이상 자가확인. null = 미확인(레거시), true = 확인됨. */
    @Column(name = "is_over_14")
    private Boolean isOver14;

    @Column(name = "age_checked_at")
    private LocalDateTime ageCheckedAt;

    // ── 2026-06-03 휴대폰 OTP 인증 (Firebase Phone Auth). 거래/채팅 신뢰 배지·게이트용. ──
    // 법적 본인확인 아님 — 이름/생년/CI/DI 미수집. 번호 소유만 확인.
    @Column(name = "phone_verified", nullable = false)
    @Builder.Default
    private boolean phoneVerified = false;

    @Column(name = "phone_e164", length = 20)
    private String phoneE164;

    @Column(name = "phone_verified_at")
    private LocalDateTime phoneVerifiedAt;

    // ── 2026-06-03 스캔 이미지 수집·활용 선택 동의 (PIPA, docs/IMAGE_DATA_STRATEGY.md). ──
    // 미동의(false) 시 scan_captures 캡처 skip. 기존 유저 기본값 false(안전).
    @Column(name = "scan_image_consent", nullable = false)
    @Builder.Default
    private boolean scanImageConsent = false;

    @Column(name = "scan_image_consent_at")
    private LocalDateTime scanImageConsentAt;

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

    /** 휴대폰 OTP 인증 완료 (Firebase Phone Auth ID토큰 검증 후 호출). 로드된 엔티티 직접 변경. */
    public void verifyPhone(String phoneE164) {
        this.phoneVerified = true;
        this.phoneE164 = phoneE164;
        this.phoneVerifiedAt = LocalDateTime.now();
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

    /** 로그인 시 이메일 변경 동기화 — 로드된 엔티티 직접변경(builder 재조립 금지: deletedAt/phone/appleId/정지 보존). */
    public void updateEmail(String email) {
        this.email = email;
    }

    /**
     * 온보딩 완료 — 로드된 엔티티를 직접 변경(재조립 금지: appleId/정지/탈퇴 필드 NULL 덮어쓰기 방지).
     * 만 14세 자가확인 필수 (한국 PIPA). 생년월일은 저장하지 않음 — 확인값만.
     */
    public void completeOnboarding(String nickname, String profileImageUrl, Boolean isOver14, LocalDateTime now) {
        if (!Boolean.TRUE.equals(isOver14)) {
            throw new IllegalArgumentException("만 14세 이상만 가입할 수 있습니다");
        }
        this.nickname = nickname;
        this.profileImageUrl = profileImageUrl;
        this.onboarded = true;
        this.nicknameChangedAt = now;
        this.isOver14 = Boolean.TRUE;
        this.ageCheckedAt = now;
    }

    /** B2-10: 프로필 사진 변경 — 쿨다운 없음(닉네임과 다름). 로드된 엔티티 직접 변경. */
    public void updateProfileImage(String url) {
        this.profileImageUrl = url;
    }

    /** 스캔 이미지 수집·활용 선택 동의 변경 — 온보딩/설정에서 호출. 로드된 엔티티 직접 변경. */
    public void setScanImageConsent(boolean agreed, LocalDateTime now) {
        this.scanImageConsent = agreed;
        this.scanImageConsentAt = agreed ? now : null;
    }

    /** 닉네임 변경 — 로드된 엔티티 직접 변경(재조립 금지). */
    public void changeNickname(String nickname, LocalDateTime now) {
        this.nickname = nickname;
        this.nicknameChangedAt = now;
    }
}
