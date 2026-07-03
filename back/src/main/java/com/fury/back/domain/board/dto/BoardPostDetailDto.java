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
        List<BoardCommentDto> comments,
        // 서버가 viewerId 기준 계산(UI 노출용, 권한은 쓰기 API 재검증). raw authorId 미노출.
        boolean mine,
        boolean canEdit,
        boolean canDelete,
        boolean canReport,
        boolean canBlock,
        // 좋아요(board_post_likes 집계). likeCount=COUNT(*), likedByMe=viewer 좋아요 여부(비로그인=false).
        boolean likedByMe,
        // 첨부 이미지 — {imageId(수정 유지용)·url(secure proxy)·sortOrder} 순. raw S3 키 미노출. 없으면 빈 리스트.
        List<BoardPostImageDto> images
) {}
