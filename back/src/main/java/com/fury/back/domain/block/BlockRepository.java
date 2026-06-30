package com.fury.back.domain.block;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface BlockRepository extends JpaRepository<Block, String> {
    List<Block> findAllByBlockerId(String blockerId);
    Optional<Block> findByBlockerIdAndBlockedId(String blockerId, String blockedId);
    boolean existsByBlockerIdAndBlockedId(String blockerId, String blockedId);
    void deleteByBlockerIdAndBlockedId(String blockerId, String blockedId);

    /**
     * 멱등 차단 — ON CONFLICT DO NOTHING. 동시 요청(다른 기기·재시도)에도 unique 위반(500) 없이 1행만 생성.
     * 반환: 삽입 행 수(1=신규, 0=이미 차단). uq_blocks_blocker_blocked 와 컬럼 일치.
     */
    @Modifying
    @Query(value = """
            INSERT INTO blocks (block_id, blocker_id, blocked_id, created_at)
            VALUES (:blockId, :blockerId, :blockedId, now())
            ON CONFLICT (blocker_id, blocked_id) DO NOTHING
            """, nativeQuery = true)
    int insertIgnoreBlock(@Param("blockId") String blockId,
                          @Param("blockerId") String blockerId,
                          @Param("blockedId") String blockedId);
}
