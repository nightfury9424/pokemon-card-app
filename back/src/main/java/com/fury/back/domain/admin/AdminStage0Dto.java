package com.fury.back.domain.admin;

import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

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
}
