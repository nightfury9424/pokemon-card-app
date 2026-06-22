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
        List<BoardCommentDto> replies
) {}
