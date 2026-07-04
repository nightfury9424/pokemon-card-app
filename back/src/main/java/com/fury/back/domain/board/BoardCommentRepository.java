package com.fury.back.domain.board;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.Collection;
import java.util.List;

public interface BoardCommentRepository extends JpaRepository<BoardComment, String> {

    /** 한 게시글의 전체 댓글(삭제 포함, 트리 조립은 서비스). 1쿼리 → N+1 없음. */
    List<BoardComment> findByPostIdOrderByCreatedAtAsc(String postId);

    /** 게시글별 활성(미삭제) 댓글 수 — 목록 commentCount 라이브 집계(1쿼리 batch). */
    @Query("""
            SELECT c.postId AS postId, COUNT(c) AS cnt
            FROM BoardComment c
            WHERE c.deletedAt IS NULL AND c.postId IN :postIds
            GROUP BY c.postId
            """)
    List<PostCommentCount> countActiveByPostIds(@Param("postIds") Collection<String> postIds);

    /** 게시글 단건 활성 댓글 수(상세용). */
    long countByPostIdAndDeletedAtIsNull(String postId);

    /**
     * 내가 (대)댓글 단, 노출 중인 게시글 post_id — 최신 댓글 활동순(MAX 댓글 시각 DESC).
     * board_posts JOIN 으로 가시성(삭제/숨김/비노출 타입) + 차단(blocks) 필터 → 반환 = 노출 글만.
     * dedup = GROUP BY post_id. ★native(JPQL 의 `SELECT DISTINCT ... ORDER BY MAX(...)` 불가 회피).
     */
    @Query(value = """
            SELECT c.post_id
            FROM board_comments c
            JOIN board_posts p ON p.post_id = c.post_id
            WHERE c.author_id = :authorId
              AND c.deleted_at IS NULL
              AND p.deleted_at IS NULL
              AND p.status = 'ACTIVE'
              AND p.type IN ('notice', 'event', 'patch', 'free')
              AND NOT EXISTS (SELECT 1 FROM blocks b
                              WHERE b.blocker_id = :authorId AND b.blocked_id = p.author_id)
            GROUP BY c.post_id
            ORDER BY MAX(c.created_at) DESC
            LIMIT :limit OFFSET :offset
            """, nativeQuery = true)
    List<String> findMyCommentedPostIds(@Param("authorId") String authorId,
                                        @Param("limit") int limit,
                                        @Param("offset") int offset);

    /** findMyCommentedPostIds 의 전체 distinct 건수(노출 글 기준) — 페이지 totalPages 정합용. */
    @Query(value = """
            SELECT COUNT(DISTINCT c.post_id)
            FROM board_comments c
            JOIN board_posts p ON p.post_id = c.post_id
            WHERE c.author_id = :authorId
              AND c.deleted_at IS NULL
              AND p.deleted_at IS NULL
              AND p.status = 'ACTIVE'
              AND p.type IN ('notice', 'event', 'patch', 'free')
              AND NOT EXISTS (SELECT 1 FROM blocks b
                              WHERE b.blocker_id = :authorId AND b.blocked_id = p.author_id)
            """, nativeQuery = true)
    long countMyCommentedPosts(@Param("authorId") String authorId);

    interface PostCommentCount {
        String getPostId();
        long getCnt();
    }
}
