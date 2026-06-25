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

    /** 같은 사용자를 같은 신고자가 이미 신고했는지 (1회 제한 — 차단 풀고 재신고 방지). USER/TRADE/CHAT 전용. */
    boolean existsByReporterIdAndTargetUserId(String reporterId, String targetUserId);

    /** ★게시판 신고 중복 = 글/댓글 단위(reporter+type+id). 같은 작성자의 서로 다른 글·댓글은 각각 신고 가능. */
    boolean existsByReporterIdAndTargetTypeAndTargetId(String reporterId, String targetType, String targetId);

    /**
     * 2026-05-29 admin Stage 0 (Codex G) — 신고 list pageable + status/targetType/시간 filter.
     *   default sort: status=PENDING newest first (idx_reports_status_created 활용).
     *   reporter / target 정보는 service 단에서 batch lookup (N+1 회피).
     */
    // 2026-06-02 fix: JPQL nullable param → PostgreSQL 42P18 (could not determine data type
    //   of parameter). 전부 null(ALL 필터) 시 admin 신고 0건으로 보이던 버그. native + CAST 로
    //   null param 타입 명시 (memory feedback_hibernate_native_param_types).
    @Query(value = """
            SELECT * FROM reports r
            WHERE (CAST(:status AS text) IS NULL OR r.status = :status)
              AND (CAST(:targetType AS text) IS NULL OR r.target_type = :targetType)
              AND (CAST(:createdFrom AS timestamp) IS NULL OR r.created_at >= :createdFrom)
              AND (CAST(:createdTo AS timestamp) IS NULL OR r.created_at < :createdTo)
            ORDER BY r.created_at DESC
            """,
            countQuery = """
            SELECT count(*) FROM reports r
            WHERE (CAST(:status AS text) IS NULL OR r.status = :status)
              AND (CAST(:targetType AS text) IS NULL OR r.target_type = :targetType)
              AND (CAST(:createdFrom AS timestamp) IS NULL OR r.created_at >= :createdFrom)
              AND (CAST(:createdTo AS timestamp) IS NULL OR r.created_at < :createdTo)
            """,
            nativeQuery = true)
    Page<Report> findAdminList(
            @Param("status") String status,
            @Param("targetType") String targetType,
            @Param("createdFrom") LocalDateTime createdFrom,
            @Param("createdTo") LocalDateTime createdTo,
            Pageable pageable);

    /** 카운트 — admin 대시보드 헤더 (PENDING 신고 수). */
    long countByStatus(String status);
}
