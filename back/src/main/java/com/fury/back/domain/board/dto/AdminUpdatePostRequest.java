package com.fury.back.domain.board.dto;

/** 관리자 공식글 부분수정(null=미변경). 공식 타입(notice/event/patch)에만 허용. */
public record AdminUpdatePostRequest(String title, String content, Boolean isPinned) {}
