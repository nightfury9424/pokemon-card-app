package com.fury.back.domain.admin;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

/**
 * 2026-05-29 admin Stage 0 audit log repository.
 *
 * <p>INSERT-only — entity 자체에 update 메서드 없음. 조회는 admin audit trail 화면용.</p>
 */
public interface AdminActionRepository extends JpaRepository<AdminAction, String> {

    /** 특정 admin 의 최근 액션 (감사 trail). */
    List<AdminAction> findTop100ByAdminUserIdOrderByCreatedAtDesc(String adminUserId);

    /**
     * 2026-06-07 운영 로그 뷰어 — actionType/targetType 선택 필터 + 최신순 페이징.
     * JPQL nullable param (string) 은 PostgreSQL 타입추론 이슈(42P18, native 한정) 영향 없음.
     */
    @Query("SELECT a FROM AdminAction a " +
           "WHERE (:actionType IS NULL OR a.actionType = :actionType) " +
           "AND (:targetType IS NULL OR a.targetType = :targetType) " +
           "ORDER BY a.createdAt DESC")
    Page<AdminAction> findFiltered(@Param("actionType") String actionType,
                                   @Param("targetType") String targetType,
                                   Pageable pageable);

    /** 특정 target 의 액션 history (e.g. 한 거래글에 대한 모든 admin 처리). */
    List<AdminAction> findByTargetTypeAndTargetIdOrderByCreatedAtDesc(String targetType, String targetId);

    /** 신고 기반 처리 audit. */
    List<AdminAction> findByReportIdOrderByCreatedAtAsc(String reportId);
}
