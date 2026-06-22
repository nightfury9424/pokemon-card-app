package com.fury.back.domain.board.dto;

import java.time.LocalDateTime;

/** 프론트 BoardPost 계약(목록용 — comments 제외). commentCount 는 라이브 집계. */
public record BoardPostSummaryDto(
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
        int commentCount
) {}
