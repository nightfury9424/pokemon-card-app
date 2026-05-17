package com.fury.back.domain.report;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ReportRepository extends JpaRepository<Report, String> {
    List<Report> findByReporterIdOrderByCreatedAtDesc(String reporterId);
    List<Report> findByTargetTypeAndTargetIdOrderByCreatedAtDesc(String targetType, String targetId);
    long countByReporterIdAndTargetTypeAndTargetIdAndStatus(
            String reporterId, String targetType, String targetId, String status);
}
