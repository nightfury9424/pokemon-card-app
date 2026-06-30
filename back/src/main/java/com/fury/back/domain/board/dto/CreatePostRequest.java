package com.fury.back.domain.board.dto;

import java.util.List;

/**
 * 사용자 게시글 작성. section/authorId/isPinned/status 는 수용하지 않음(서버 결정).
 * imageUploadIds = board_image_uploads 의 uploadId(raw storage key 직접 연결 불가 — 서버가 소유권·일회성 검증 후 consume).
 */
public record CreatePostRequest(String type, String title, String content, List<String> imageUploadIds) {
    public CreatePostRequest(String type, String title, String content) {
        this(type, title, content, List.of());
    }
}
