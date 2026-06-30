package com.fury.back.domain.board;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 게시판 댓글. 1단 답글만(parentCommentId != null = 답글, 부모는 반드시 최상위).
 * Slice 1A 는 조회만 — 등록/삭제는 이후 슬라이스.
 */
@Entity
@Table(name = "board_comments")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class BoardComment {

    @Id
    @Column(name = "comment_id", length = 50)
    private String commentId;

    @Column(name = "post_id", nullable = false, length = 50)
    private String postId;

    /** NULL = 최상위 댓글, 값 = 1단 답글의 부모 commentId. */
    @Column(name = "parent_comment_id", length = 50)
    private String parentCommentId;

    @Column(name = "author_id", nullable = false, length = 50)
    private String authorId;

    @Column(name = "content", nullable = false, columnDefinition = "TEXT")
    private String content;

    @Column(name = "is_admin", nullable = false)
    private boolean admin;

    @Column(name = "is_accepted", nullable = false)
    private boolean accepted;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }

    public boolean isDeleted() {
        return deletedAt != null;
    }

    public boolean isTopLevel() {
        return parentCommentId == null;
    }

    /** 소프트삭제. */
    public void softDelete() {
        this.deletedAt = LocalDateTime.now();
    }

    /** 복구(deleted_at 클리어). 댓글은 status 컬럼 없음 → delete/restore 단일 축. */
    public void restore() {
        this.deletedAt = null;
    }
}
