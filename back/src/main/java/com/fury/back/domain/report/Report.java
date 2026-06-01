package com.fury.back.domain.report;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "reports")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Report {

    @Id
    @Column(name = "report_id", length = 50)
    private String reportId;

    @Column(name = "reporter_id", nullable = false, length = 50)
    private String reporterId;

    /** TRADE / USER / BUY_ORDER / CHAT */
    @Column(name = "target_type", nullable = false, length = 20)
    private String targetType;

    @Column(name = "target_id", nullable = false, length = 50)
    private String targetId;

    /** FRAUD / FAKE / ABUSIVE_PRICE / INSULT / SPAM / OTHER */
    @Column(name = "reason", nullable = false, length = 40)
    private String reason;

    @Column(name = "detail", columnDefinition = "TEXT")
    private String detail;

    /** PENDING / REVIEWED / RESOLVED / DISMISSED */
    @Column(name = "status", nullable = false, length = 20)
    private String status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "reviewed_at")
    private LocalDateTime reviewedAt;

    // 2026-05-29 Stage 0 (Codex B) — admin 처리 메타 4 컬럼.
    @Column(name = "admin_memo", columnDefinition = "TEXT")
    private String adminMemo;

    @Column(name = "handled_by", length = 50)
    private String handledBy;

    @Column(name = "handled_at")
    private LocalDateTime handledAt;

    /** SUSPEND_USER / DELETE_TRADE / DELETE_CHAT / DISMISS / NONE. */
    @Column(name = "resolution_action", length = 40)
    private String resolutionAction;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (status == null) status = "PENDING";
    }

    /** 2026-05-29: admin 처리 — status 변경 + 메타 기록. AdminActionService 에서 호출. */
    public void markHandled(String newStatus, String adminUserId, String memo, String resolutionAction) {
        this.status = newStatus;
        this.handledBy = adminUserId;
        this.handledAt = LocalDateTime.now();
        this.adminMemo = memo;
        this.resolutionAction = resolutionAction;
        // 기존 reviewed_at 도 set (backward compat — legacy 코드 호환).
        if ("REVIEWED".equals(newStatus) || "RESOLVED".equals(newStatus) || "DISMISSED".equals(newStatus)) {
            this.reviewedAt = LocalDateTime.now();
        }
    }
}
