package com.fury.back.domain.user;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 탈퇴 사용자 audit — 탈퇴 시 users 행에서 마스킹되어 사라지는 원본 PII를 admin 전용으로 보관.
 *
 * 정책 (docs/DELETION_POLICY.md):
 *  - users 행: nickname/email/profileImageUrl 마스킹(App Review 5.1.1 준수).
 *  - 원본 PII + social id 는 여기에 보관 → admin이 분쟁/사기 대응 시 조회 (3개월/90일).
 *  - purge cron 이 purgeAfter 경과 audit 의 유저 데이터 완전 삭제(true deletion) + audit row 삭제.
 *  - 법적근거: 전자상거래법 §6(거래기록 3개월 보존) · 사기/분쟁 대응(정당한 이익).
 *  - social id 는 재가입 감지/쿨다운용으로 보관하되 admin API 응답엔 미노출.
 *
 * users.user_id 와 FK 없음 — purge 시 user 행을 먼저 hard-delete 하고 audit를 마지막에 지우므로
 * FK 제약이 삭제 순서를 막으면 안 됨.
 */
@Entity
@Table(name = "deleted_user_audit")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class DeletedUserAudit {

    @Id
    @Column(name = "user_id", length = 50)
    private String userId;

    @Column(name = "original_nickname", length = 50)
    private String originalNickname;

    @Column(name = "original_email", length = 200)
    private String originalEmail;

    @Column(name = "original_profile_image_url", length = 500)
    private String originalProfileImageUrl;

    @Column(name = "original_google_id", length = 100)
    private String originalGoogleId;

    @Column(name = "original_apple_id", length = 100)
    private String originalAppleId;

    @Column(name = "deleted_at", nullable = false)
    private LocalDateTime deletedAt;

    @Column(name = "purge_after", nullable = false)
    private LocalDateTime purgeAfter;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (this.createdAt == null) this.createdAt = LocalDateTime.now();
    }

    /**
     * 마스킹 전 User 엔티티에서 audit 생성. ★markDeletedAndMask 호출 전에 불러야 원본이 잡힘.
     * purgeAfter = deletedAt + retentionDays.
     */
    public static DeletedUserAudit capture(User user, LocalDateTime deletedAt, int retentionDays) {
        return DeletedUserAudit.builder()
                .userId(user.getUserId())
                .originalNickname(user.getNickname())
                .originalEmail(user.getEmail())
                .originalProfileImageUrl(user.getProfileImageUrl())
                .originalGoogleId(user.getGoogleId())
                .originalAppleId(user.getAppleId())
                .deletedAt(deletedAt)
                .purgeAfter(deletedAt.plusDays(retentionDays))
                .createdAt(LocalDateTime.now())
                .build();
    }
}
