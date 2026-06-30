package com.fury.back.domain.board;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface BoardPostViewRepository extends JpaRepository<BoardPostView, BoardPostView.Pk> {

    /**
     * 조회 기록 멱등 INSERT. 이미 (post_id, viewer_id) 있으면 no-op(0행).
     * 반환 affected rows == 1 일 때만 신규 조회 → 호출부가 view_count + 1.
     */
    @Modifying
    @Query(value = "INSERT INTO board_post_views (post_id, viewer_id, viewed_at) "
            + "VALUES (:postId, :viewerId, now()) ON CONFLICT DO NOTHING", nativeQuery = true)
    int insertIgnore(@Param("postId") String postId, @Param("viewerId") String viewerId);
}
