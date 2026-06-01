package com.fury.back.domain.admin;

import com.fury.back.common.ApiResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

/**
 * 2026-05-29 admin Stage 0 REST endpoint 모음.
 *
 * <p>모두 /api/admin/** 아래 — {@code AdminAllowlistFilter} 자동 통과 검증.
 * 비-admin 사용자는 filter 단에서 403. /api/admin/whoami 도 동일 — 비-admin은 403 응답이라
 * Flutter 가 admin tab 숨김 처리 (Codex A, K).</p>
 */
@RestController
@RequestMapping("/api/admin")
@RequiredArgsConstructor
public class AdminStage0Controller {

    private final AdminStage0Service service;

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/whoami
    // 비-admin 은 filter 단에서 403 — 여기는 admin 통과 케이스만 도달.
    // ─────────────────────────────────────────────────────────────────────
    @GetMapping("/whoami")
    public ApiResponse<AdminStage0Dto.WhoAmI> whoami(@AuthenticationPrincipal String userId) {
        return ApiResponse.ok(service.whoami(userId));
    }

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/reports
    // ─────────────────────────────────────────────────────────────────────
    @GetMapping("/reports")
    public ApiResponse<Map<String, Object>> listReports(
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String targetType,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime createdFrom,
            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE_TIME) LocalDateTime createdTo,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        Page<AdminStage0Dto.ReportRow> result = service.listReports(
                status, targetType, createdFrom, createdTo, page, size);
        return ApiResponse.ok(Map.of(
                "content", result.getContent(),
                "totalElements", result.getTotalElements(),
                "totalPages", result.getTotalPages(),
                "page", result.getNumber(),
                "size", result.getSize(),
                "pendingCount", service.countByStatus("PENDING")));
    }

    @PatchMapping("/reports/{reportId}/status")
    public ApiResponse<AdminStage0Dto.ReportRow> updateReportStatus(
            @PathVariable String reportId,
            @AuthenticationPrincipal String userId,
            @RequestBody AdminStage0Dto.ReportStatusUpdate body) {
        return ApiResponse.ok(service.updateReportStatus(reportId, userId, body));
    }

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/users/search
    // ─────────────────────────────────────────────────────────────────────
    @GetMapping("/users/search")
    public ApiResponse<List<AdminStage0Dto.UserRow>> searchUsers(
            @RequestParam String q,
            @RequestParam(defaultValue = "20") int size) {
        return ApiResponse.ok(service.searchUsers(q, size));
    }

    @PostMapping("/users/{userId}/suspend")
    public ApiResponse<AdminStage0Dto.UserRow> suspendUser(
            @PathVariable String userId,
            @AuthenticationPrincipal String adminUserId,
            @RequestBody AdminStage0Dto.SuspendBody body) {
        return ApiResponse.ok(service.suspendUser(userId, adminUserId, body.getReason()));
    }

    @PostMapping("/users/{userId}/unsuspend")
    public ApiResponse<AdminStage0Dto.UserRow> unsuspendUser(
            @PathVariable String userId,
            @AuthenticationPrincipal String adminUserId) {
        return ApiResponse.ok(service.unsuspendUser(userId, adminUserId));
    }

    // ─────────────────────────────────────────────────────────────────────
    // DELETE /api/admin/trade-posts/{id}
    // ─────────────────────────────────────────────────────────────────────
    @DeleteMapping("/trade-posts/{tradeId}")
    public ApiResponse<Void> deleteTradePost(
            @PathVariable String tradeId,
            @AuthenticationPrincipal String adminUserId,
            @RequestBody(required = false) AdminStage0Dto.DeleteTradeBody body) {
        service.adminDeleteTradePost(tradeId, adminUserId,
                body != null ? body.getReason() : null);
        return ApiResponse.ok();
    }
}
