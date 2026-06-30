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
        int commentCount,
        // 서버가 viewerId 기준 계산(UI 노출용, 권한은 쓰기 API 재검증). raw authorId 미노출.
        boolean mine,
        boolean canEdit,
        boolean canDelete,
        boolean canReport,
        boolean canBlock,
        // 좋아요(board_post_likes 집계). likeCount=COUNT(*), likedByMe=viewer 좋아요 여부(비로그인=false).
        boolean likedByMe,
        // 목록 썸네일 — 첫 이미지(sort 0) secure proxy URL(없으면 null) + 총 첨부 수. raw S3 키·전체 배열 미노출.
        String thumbnailUrl,
        int imageCount
) {}
