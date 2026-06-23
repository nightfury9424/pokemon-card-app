package com.fury.back.domain.board.dto;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 프론트 BoardComment 계약. 삭제 댓글(답글 보유)은 placeholder 노드로 채워 non-null 필드 보장.
 */
public record BoardCommentDto(
        String id,
        String author,
        String body,
        LocalDateTime createdAt,
        boolean isAdmin,
        boolean isAccepted,
        List<BoardCommentDto> replies,
        // 서버가 viewerId 기준 계산(UI 노출용, 권한은 쓰기 API 재검증). raw authorId 미노출.
        boolean mine,
        boolean canDelete,
        boolean canReply,
        // 답글 작성 시 항상 이 id(최상위 댓글)로 전송 → 2단 이상 방지. 삭제 댓글=null.
        String replyTargetCommentId,
        boolean canReport,
        boolean canBlock
) {}
