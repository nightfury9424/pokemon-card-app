package com.fury.back.domain.report;

import java.util.List;

/**
 * 신고 당시 게시판 원문 immutable snapshot(reports.reported_snapshot JSONB).
 * 신고 생성 시 서버가 1회 채우고 이후 절대 갱신 안 함. 자유글 수정/삭제·닉네임 변경 후에도 신고 시점 증거를 보존한다.
 *
 * <p>타임스탬프는 ISO 문자열(Hibernate JSON 직렬화 안전 — LocalDateTime 모듈 의존 제거). raw authorId 미포함.
 * BOARD_POST = 제목/본문 필드, BOARD_COMMENT = postTitle/thread 필드 사용(미해당 필드는 null).
 */
public record ReportedSnapshot(
        int version,
        String targetType,           // BOARD_POST / BOARD_COMMENT
        // ── BOARD_POST ──
        String title,
        String content,
        String authorLabel,          // 공식글=운영팀 / 일반=닉네임 / 누락=(알 수 없음). raw id 아님.
        String targetCreatedAt,      // ISO
        String targetUpdatedAt,      // ISO (없으면 null)
        // ── BOARD_COMMENT ──
        String postTitle,
        String targetCommentId,
        String topCommentId,
        List<SnapshotComment> comments // 신고 당시 최상위 thread(최상위 + 그 대댓글만, unrelated 제외)
) {
    public record SnapshotComment(
            String commentId,
            String parentCommentId,
            String authorLabel,
            String content,
            String createdAt         // ISO
    ) {}

    public static final int CURRENT_VERSION = 1;

    /**
     * targetType 별 필수 필드 충족 여부(version 무관 구조 검증).
     * BOARD_POST=title·content / BOARD_COMMENT=targetCommentId·topCommentId·comments(절대 null 금지).
     * 미충족 = INVALID — 생성 시 저장 거부, 조회 시 관리자 오류 상태(레거시 null 과 구분).
     */
    public boolean hasRequiredFields() {
        if ("BOARD_POST".equals(targetType)) {
            return title != null && content != null;
        }
        if ("BOARD_COMMENT".equals(targetType)) {
            return targetCommentId != null && topCommentId != null && comments != null;
        }
        return false;
    }
}
