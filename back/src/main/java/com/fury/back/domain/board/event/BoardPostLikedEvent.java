package com.fury.back.domain.board.event;

/** 게시글 좋아요 신규 INSERT 성공 시 발행. AFTER_COMMIT 리스너가 게시글 작성자에게 알림. */
public record BoardPostLikedEvent(String postId, String postAuthorId, String actorId) {}
