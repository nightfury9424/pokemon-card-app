package com.fury.back.domain.board.dto;

/** 조회 기록 응답. counted=이번 요청으로 신규 조회 집계 여부, viewCount=최신 조회수. */
public record BoardViewResponse(boolean counted, int viewCount) {}
