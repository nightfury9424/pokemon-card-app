package com.fury.back.domain.board.dto;

/** 댓글/1단 답글 작성. parentCommentId 있으면 답글(같은 게시글의 최상위·미삭제 댓글이어야 함). */
public record CreateCommentRequest(String content, String parentCommentId) {}
