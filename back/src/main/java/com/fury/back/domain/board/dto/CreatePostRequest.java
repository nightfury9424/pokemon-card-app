package com.fury.back.domain.board.dto;

/** 사용자 게시글 작성. section/authorId/isPinned/status 는 수용하지 않음(서버 결정). */
public record CreatePostRequest(String type, String title, String content) {}
