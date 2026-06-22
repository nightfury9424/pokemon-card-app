package com.fury.back.domain.board;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 게시판 게시글. Slice 1A(읽기 토대) — 작성/수정/삭제·좋아요·조회수증가는 이후 슬라이스.
 * type 토큰은 프론트 enum(notice/event/patch/free/tradeReview/scamAlert/qna)과 동일하게 저장/직렬화.
 * section 은 type 에서 도출(official/community/qna), 작성 시 검증(BoardTaxonomy).
 */
@Entity
@Table(name = "board_posts")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class BoardPost {

    @Id
    @Column(name = "post_id", length = 50)
    private String postId;

    @Column(name = "type", nullable = false, length = 20)
    private String type;

    @Column(name = "section", nullable = false, length = 20)
    private String section;

    @Column(name = "title", nullable = false, length = 200)
    private String title;

    @Column(name = "content", nullable = false, columnDefinition = "TEXT")
    private String content;

    @Column(name = "author_id", nullable = false, length = 50)
    private String authorId;

    @Column(name = "is_pinned", nullable = false)
    private boolean pinned;

    @Column(name = "is_answered", nullable = false)
    private boolean answered;

    @Column(name = "view_count", nullable = false)
    private int viewCount;

    @Column(name = "like_count", nullable = false)
    private int likeCount;

    /** ACTIVE / HIDDEN (모더레이션). 읽기 노출은 ACTIVE 만. */
    @Column(name = "status", nullable = false, length = 20)
    private String status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at")
    private LocalDateTime updatedAt;

    /** 소프트삭제. NULL = 노출. */
    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (status == null) status = "ACTIVE";
    }
}
