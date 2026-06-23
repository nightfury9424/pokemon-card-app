package com.fury.back.domain.board.dto;

/** 좋아요/취소(멱등 PUT/DELETE) 응답. likeCount = board_post_likes COUNT(*). */
public record BoardLikeResponse(boolean likedByMe, long likeCount) {}
