package com.fury.back.domain.admin;

import lombok.Builder;
import lombok.Getter;

import com.fury.back.domain.report.ReportedSnapshot;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 2026-05-29 admin Stage 0 응답 DTO 모음.
 *
 * <p>모두 inner static class — Stage 0 한정. v1.1 확장 시 별도 파일 분리.</p>
 */
public class AdminStage0Dto {

    /** GET /api/admin/whoami — 단순 boolean + 사이드바 footer 표시용 닉네임. */
    @Getter
    @Builder
    public static class WhoAmI {
        private boolean isAdmin;
        private String userId;
        // 2026-05-29 P-1: 사이드바 footer "관리자/admin" 하드코딩 제거용. 비-admin 케이스는 filter 단에서 403이라
        // 도달 자체를 안 함 → null 걱정 없음 (단 신규 가입 직후 nickname 미설정 가능 → null 그레이스).
        private String nickname;
        private String email;
    }

    /** GET /api/admin/reports — 신고 list row. reporter/target 정보 join projection (Codex G). */
    @Getter
    @Builder
    public static class ReportRow {
        private String reportId;
        private String reporterId;
        private String reporterNickname;      // batch lookup
        private String targetType;             // TRADE / USER / BUY_ORDER / CHAT
        private String targetId;
        private String targetSummary;          // 거래글 title / 사용자 닉네임 / chatRoomId 등 — batch lookup
        private String reason;
        private String detail;
        private String status;                  // PENDING / REVIEWED / RESOLVED / DISMISSED
        private String adminMemo;
        private String handledBy;
        private LocalDateTime handledAt;
        private String resolutionAction;
        private LocalDateTime createdAt;
    }

    /** PATCH /api/admin/reports/{id}/status — body. */
    @Getter
    public static class ReportStatusUpdate {
        private String status;             // REVIEWED / RESOLVED / DISMISSED
        private String adminMemo;
        private String resolutionAction;   // SUSPEND_USER / DELETE_TRADE / DISMISS / NONE
    }

    /** GET /api/admin/users/search?q= — 사용자 list row. */
    @Getter
    @Builder
    public static class UserRow {
        private String userId;
        private String nickname;
        private String email;                  // soft-deleted 면 null
        private boolean suspended;
        private LocalDateTime suspendedAt;
        private String suspensionReason;
        private boolean deleted;               // deleted_at NOT NULL
        private LocalDateTime createdAt;
        private long warningCount;             // 활성 경고 수 (모더레이션)
        private boolean autoSuspended;         // 이번 경고로 임계치 도달해 자동 정지됐는지
    }

    /** POST /api/admin/users/{id}/suspend — body. */
    @Getter
    public static class SuspendBody {
        private String reason;
    }

    /** DELETE /api/admin/trade-posts/{id} — body (선택). */
    @Getter
    public static class DeleteTradeBody {
        private String reason;
    }

    /** POST /api/admin/users/{id}/warn — body. reportId 는 근거 신고(선택). */
    @Getter
    public static class WarnBody {
        private String reason;
        private String reportId;
    }

    /** GET /api/admin/admin-actions — 운영(감사) 로그 row. (2026-06-07 관측성 Phase 1) */
    @Getter
    @Builder
    public static class AdminActionRow {
        private String actionId;
        private String adminUserId;
        private String adminNickname;       // batch lookup (없으면 null)
        private String actionType;          // SUSPEND / UNSUSPEND / WARN / AUTO_SUSPEND / DELETE_TRADE / REVIEW_REPORT ...
        private String targetType;          // USER / TRADE / REPORT / CHAT_MESSAGE
        private String targetId;
        private String reportId;            // 신고 근거 (선택)
        private String memo;
        private String previousState;
        private String newState;
        private LocalDateTime createdAt;
    }

    // ── 게시판 신고 원문·문맥 (GET /reports/{id}/target-context) — 파괴적 조치 전 관리자 확인용 ──
    @Getter
    @Builder
    public static class TargetContext {
        private String reportId;
        private String targetType;          // BOARD_POST / BOARD_COMMENT
        private String targetId;
        private boolean available;          // 현재 콘텐츠 존재 여부(false=물리 삭제/미존재)
        private BoardPostView post;         // 현재 — BOARD_POST=신고 게시글 / BOARD_COMMENT=원문 게시글
        private BoardCommentThread thread;  // 현재 — BOARD_COMMENT 만(최상위 thread + 대상 강조)
        // 신고 당시 증거
        private boolean snapshotAvailable;  // 신고 당시 snapshot 보존 여부(false=이전 신고, 비교 불가)
        private boolean changedSinceReport; // snapshot vs 현재 내용 상이(snapshot 없으면 false)
        private ReportedSnapshot reportedSnapshot; // 신고 당시 원문(불변). 없으면 null.
    }

    @Getter
    @Builder
    public static class BoardPostView {
        private String postId;
        private String type;
        private String title;
        private String content;
        private String authorLabel;     // 표시명(공식글=운영팀, 그 외=닉네임)
        private String status;          // ACTIVE / HIDDEN
        private boolean hidden;         // status==HIDDEN
        private boolean deleted;        // deletedAt != null
        private LocalDateTime createdAt;
    }

    @Getter
    @Builder
    public static class BoardCommentThread {
        private String targetCommentId; // 신고된 댓글(강조용)
        private String topCommentId;
        private List<BoardCommentView> comments; // 최상위 + 그 아래 대댓글만(unrelated 제외)
    }

    @Getter
    @Builder
    public static class BoardCommentView {
        private String commentId;
        private String parentCommentId;
        private String authorLabel;
        private String content;
        private boolean deleted;
        private boolean target;         // 신고된 댓글
        private LocalDateTime createdAt;
    }
}
