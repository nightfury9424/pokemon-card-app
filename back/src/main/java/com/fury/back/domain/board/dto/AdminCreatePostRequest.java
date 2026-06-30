package com.fury.back.domain.board.dto;

/** 관리자 공식글 작성. authorId 는 무시(서버가 인증된 관리자 userId 로 결정). */
public record AdminCreatePostRequest(String type, String title, String content, Boolean isPinned) {}
