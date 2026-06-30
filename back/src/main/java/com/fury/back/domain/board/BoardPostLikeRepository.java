package com.fury.back.domain.board;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;

public interface BoardPostLikeRepository extends JpaRepository<BoardPostLike, String> {

    /**
     * 멱등 INSERT — UNIQUE(post_id,user_id) 충돌 시 무시(동시성 안전). 영향 행수(1=신규, 0=이미 존재) 반환.
     * native 라 즉시 실행 → 동일 트랜잭션의 후속 COUNT 가 반영본을 본다.
     */
    @Modifying
    @Query(value = """
            INSERT INTO board_post_likes (like_id, post_id, user_id, created_at)
            VALUES (:likeId, :postId, :userId, NOW())
            ON CONFLICT (post_id, user_id) DO NOTHING
            """, nativeQuery = true)
    int insertIgnore(@Param("likeId") String likeId,
                     @Param("postId") String postId,
                     @Param("userId") String userId);

    /** 멱등 DELETE — 0/1행. 영향 행수 반환. */
    @Modifying
    @Query("DELETE FROM BoardPostLike l WHERE l.postId = :postId AND l.userId = :userId")
    int deleteByPostIdAndUserId(@Param("postId") String postId, @Param("userId") String userId);

    long countByPostId(String postId);

    boolean existsByPostIdAndUserId(String postId, String userId);

    /** 여러 게시글 좋아요 수 batch — N+1 방지. 각 row = [postId, count]. (빈 목록 호출 금지 — 호출측 가드.) */
    @Query("SELECT l.postId, COUNT(l) FROM BoardPostLike l WHERE l.postId IN :postIds GROUP BY l.postId")
    List<Object[]> countByPostIdIn(@Param("postIds") Collection<String> postIds);

    /** viewer 가 좋아요한 postId batch — N+1 방지. (빈 목록 호출 금지.) */
    @Query("SELECT l.postId FROM BoardPostLike l WHERE l.userId = :userId AND l.postId IN :postIds")
    List<String> findLikedPostIds(@Param("userId") String userId, @Param("postIds") Collection<String> postIds);
}
