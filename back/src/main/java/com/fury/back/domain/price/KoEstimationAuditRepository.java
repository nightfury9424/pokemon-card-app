package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDate;
import java.util.Collection;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

public interface KoEstimationAuditRepository extends JpaRepository<KoEstimationAudit, UUID> {

    /** snapshot_id 기준 단건 조회 (랭킹 SQL JOIN 시 기본 키). */
    Optional<KoEstimationAudit> findByKoSnapshotId(String koSnapshotId);

    /** prev audit batch 조회 — 전일 latest KO snapshot의 audit들 (보완 4 적용). */
    List<KoEstimationAudit> findByKoSnapshotIdIn(Collection<String> koSnapshotIds);

    /**
     * 특정 카드의 특정 날짜 audit 중 latest 1건.
     * 같은 날짜 multiple refresh 시 가장 최신 audit 사용.
     */
    @Query("""
            SELECT a FROM KoEstimationAudit a
            WHERE a.cardId = :cardId AND a.estimatedDate = :date
            ORDER BY a.createdAt DESC
            """)
    List<KoEstimationAudit> findLatestByCardIdAndDate(
            @Param("cardId") String cardId,
            @Param("date") LocalDate date);

    /** 날짜 범위 audit 삭제 (재backfill 전. FK CASCADE라 price_snapshots 삭제로 자동 처리되지만 명시 가능). */
    void deleteByEstimatedDateBetween(LocalDate from, LocalDate to);
}
