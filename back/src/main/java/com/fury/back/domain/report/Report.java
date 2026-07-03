package com.fury.back.domain.report;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

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

    /** 신고된 사용자 id (1회 제한 dedup용). CHAT=상대, TRADE=판매자, USER=대상. null=해석불가. */
    @Column(name = "target_user_id", length = 50)
    private String targetUserId;

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

    /** 신고 당시 게시판 원문 immutable snapshot(BOARD_POST/BOARD_COMMENT 만, 그 외 null). 생성 시 1회만 저장. */
    @JdbcTypeCode(SqlTypes.JSON)
    @Column(name = "reported_snapshot", columnDefinition = "jsonb")
    private ReportedSnapshot reportedSnapshot;

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
