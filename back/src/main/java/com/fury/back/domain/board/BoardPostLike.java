package com.fury.back.domain.board;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 게시판 좋아요 (자유글 전용). board_post_likes 가 좋아요의 source of truth — likeCount = COUNT(*).
 * board_posts.like_count 컬럼은 legacy/미사용(이 기능에서 읽지·쓰지 않음).
 * 중복은 UNIQUE(post_id,user_id) 로 차단(멱등 INSERT ... ON CONFLICT). 물리 FK 없음(기존 board 관례).
 */
@Entity
@Table(
        name = "board_post_likes",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_board_post_likes_post_user",
                columnNames = {"post_id", "user_id"}
        )
)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class BoardPostLike {

    @Id
    @Column(name = "like_id", length = 50)
    private String likeId;

    @Column(name = "post_id", nullable = false, length = 50)
    private String postId;

    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
