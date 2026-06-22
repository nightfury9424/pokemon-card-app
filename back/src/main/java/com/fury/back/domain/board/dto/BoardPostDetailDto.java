package com.fury.back.domain.board.dto;

import java.time.LocalDateTime;
import java.util.List;

/** 프론트 BoardPost 상세 계약 = 요약 필드 + 댓글 트리(1단 답글). */
public record BoardPostDetailDto(
        String id,
        String type,
        String title,
        String body,
        String author,
        LocalDateTime createdAt,
        int viewCount,
        int likeCount,
        boolean isPinned,
        boolean isAnswered,
        int commentCount,
        List<BoardCommentDto> comments
) {}
