package com.fury.back.domain.board;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface BoardPostRepository extends JpaRepository<BoardPost, String> {

    /**
     * 활성 피드. 노출 = deleted_at IS NULL AND status='ACTIVE'.
     * section/type 는 옵셔널(null=미필터). viewerId 있으면 차단(Block) author 제외.
     * 정렬 = 핀 우선 → 최신 → post_id(고유 보조키, 동일 시각 페이지 안정성).
     */
    @Query(value = """
            SELECT p FROM BoardPost p
            WHERE p.deletedAt IS NULL AND p.status = 'ACTIVE'
              AND p.type IN ('notice', 'event', 'patch', 'free')
              AND (:section IS NULL OR p.section = :section)
              AND (:type IS NULL OR p.type = :type)
              AND (:q IS NULL OR LOWER(p.title) LIKE :q)
              AND (:pinnedOnly = false OR p.pinned = true)
              AND (:viewerId IS NULL OR NOT EXISTS (
                    SELECT 1 FROM com.fury.back.domain.block.Block b
                    WHERE b.blockerId = :viewerId AND b.blockedId = p.authorId))
            ORDER BY p.pinned DESC, p.createdAt DESC, p.postId DESC
            """,
            countQuery = """
            SELECT COUNT(p) FROM BoardPost p
            WHERE p.deletedAt IS NULL AND p.status = 'ACTIVE'
              AND p.type IN ('notice', 'event', 'patch', 'free')
              AND (:section IS NULL OR p.section = :section)
              AND (:type IS NULL OR p.type = :type)
              AND (:q IS NULL OR LOWER(p.title) LIKE :q)
              AND (:pinnedOnly = false OR p.pinned = true)
              AND (:viewerId IS NULL OR NOT EXISTS (
                    SELECT 1 FROM com.fury.back.domain.block.Block b
                    WHERE b.blockerId = :viewerId AND b.blockedId = p.authorId))
            """)
    Page<BoardPost> findFeed(@Param("section") String section,
                             @Param("type") String type,
                             @Param("q") String q,
                             @Param("pinnedOnly") boolean pinnedOnly,
                             @Param("viewerId") String viewerId,
                             Pageable pageable);

    /** ★단일 상단 고정 불변식 — 대상 외 공식글 고정 전부 해제. 반환=해제된 행 수. */
    @Modifying(clearAutomatically = true, flushAutomatically = true)
    @Query("UPDATE BoardPost p SET p.pinned = false WHERE p.section = 'official' AND p.pinned = true AND p.postId <> :keepId")
    int unpinAllOfficialExcept(@Param("keepId") String keepId);

    /** 공식 고정 토글 직렬화 — 동시 ON 요청에도 ≤1개만 고정되도록 트랜잭션 advisory lock(동일 키). */
    @Query(value = "SELECT pg_advisory_xact_lock(5417)", nativeQuery = true)
    void lockOfficialPin();
}
