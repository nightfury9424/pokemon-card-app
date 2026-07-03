package com.fury.back.domain.board.event;

/**
 * 댓글/대댓글 생성 시 발행. parentCommentId == null = 최상위 댓글, != null = 대댓글.
 * AFTER_COMMIT 리스너가 수신자(게시글 작성자/부모 댓글 작성자)에게 알림(self·차단·중복 제외).
 */
public record BoardCommentCreatedEvent(
        String postId,
        String commentId,
        String actorId,
        String postAuthorId,
        String parentCommentId,
        String parentAuthorId) {}
