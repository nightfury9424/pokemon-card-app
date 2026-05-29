package com.fury.back.domain.admin;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 2026-05-29 admin Stage 0 (Codex I) — 모든 admin 액션 immutable audit log.
 *
 * <p>App Review 5.1.5 moderation workflow evidence 의무. report 기반 처리뿐 아니라
 * 직접 액션(검색 후 정지, 거래글 직접 삭제 등)도 모두 기록.</p>
 *
 * <p>설계 원칙:
 * <ul>
 *   <li>immutable — update 메서드 없음. INSERT only.
 *   <li>report_id 는 nullable — 신고 없이 직접 처리한 경우 NULL.
 *   <li>previous_state/new_state — 변경 전후 상태 스냅 (e.g. "OPEN" → "DELETED").
 *   <li>metadata_json — 추가 컨텍스트 (선택).
 * </ul>
 */
@Entity
@Table(name = "admin_actions")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class AdminAction {

    @Id
    @Column(name = "action_id", length = 50)
    private String actionId;

    @Column(name = "admin_user_id", nullable = false, length = 50)
    private String adminUserId;

    /** SUSPEND / UNSUSPEND / DELETE_TRADE / DELETE_CHAT_MESSAGE / DISMISS_REPORT / REVIEW_REPORT 등. */
    @Column(name = "action_type", nullable = false, length = 40)
    private String actionType;

    /** USER / TRADE / REPORT / CHAT_MESSAGE. */
    @Column(name = "target_type", nullable = false, length = 20)
    private String targetType;

    @Column(name = "target_id", nullable = false, length = 50)
    private String targetId;

    /** 신고 기반 처리 시 link. 직접 처리는 NULL. */
    @Column(name = "report_id", length = 50)
    private String reportId;

    @Column(name = "memo", columnDefinition = "TEXT")
    private String memo;

    /** 변경 전 상태 스냅 (e.g. "ACTIVE", "OPEN"). */
    @Column(name = "previous_state", length = 40)
    private String previousState;

    /** 변경 후 상태 스냅 (e.g. "SUSPENDED", "DELETED"). */
    @Column(name = "new_state", length = 40)
    private String newState;

    /** 추가 컨텍스트 (JSON 직렬화). */
    @Column(name = "metadata_json", columnDefinition = "TEXT")
    private String metadataJson;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
