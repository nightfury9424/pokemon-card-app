package com.fury.back.domain.board.dto;

/** 게시글 모더레이션. action: HIDE/UNHIDE(status 축) · RESTORE(deleted_at NULL 만, status 불변). */
public record PostModerationRequest(String action) {}
