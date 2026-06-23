package com.fury.back.domain.board.dto;

/** 사용자 본인 글 수정(제목·본문만). type 변경 불가(official 승격 차단). */
public record UpdatePostRequest(String title, String content) {}
