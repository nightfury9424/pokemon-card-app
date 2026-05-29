package com.fury.back.domain.report;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

public interface ReportRepository extends JpaRepository<Report, String> {
    List<Report> findByReporterIdOrderByCreatedAtDesc(String reporterId);
    List<Report> findByTargetTypeAndTargetIdOrderByCreatedAtDesc(String targetType, String targetId);
    long countByReporterIdAndTargetTypeAndTargetIdAndStatus(
            String reporterId, String targetType, String targetId, String status);

    /**
     * 2026-05-29 admin Stage 0 (Codex G) — 신고 list pageable + status/targetType/시간 filter.
     *   default sort: status=PENDING newest first (idx_reports_status_created 활용).
     *   reporter / target 정보는 service 단에서 batch lookup (N+1 회피).
     */
    @Query("""
            SELECT r FROM Report r
            WHERE (:status IS NULL OR r.status = :status)
              AND (:targetType IS NULL OR r.targetType = :targetType)
              AND (:createdFrom IS NULL OR r.createdAt >= :createdFrom)
              AND (:createdTo IS NULL OR r.createdAt < :createdTo)
            ORDER BY r.createdAt DESC
            """)
    Page<Report> findAdminList(
            @Param("status") String status,
            @Param("targetType") String targetType,
            @Param("createdFrom") LocalDateTime createdFrom,
            @Param("createdTo") LocalDateTime createdTo,
            Pageable pageable);

    /** 카운트 — admin 대시보드 헤더 (PENDING 신고 수). */
    long countByStatus(String status);
}
