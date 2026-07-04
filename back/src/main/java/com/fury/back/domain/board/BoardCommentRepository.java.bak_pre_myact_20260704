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

    interface PostCommentCount {
        String getPostId();
        long getCnt();
    }
}
