package com.fury.back.domain.admin;

import com.fury.back.auth.AdminAllowlistFilter;
import com.fury.back.domain.chat.ChatService;
import com.fury.back.domain.report.Report;
import com.fury.back.domain.report.ReportRepository;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * 2026-05-29 admin Stage 0 service — 신고 처리 / 사용자 정지 / 거래글 삭제 통합.
 * <p>모든 mutation은 {@link AdminActionService#record} 로 audit log 기록.</p>
 */
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AdminStage0Service {

    private final ReportRepository reportRepository;
    private final UserRepository userRepository;
    private final TradePostRepository tradePostRepository;
    private final AdminAllowlistFilter adminAllowlistFilter;
    private final AdminActionService adminActionService;
    private final ChatService chatService;

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/whoami
    // ─────────────────────────────────────────────────────────────────────

    public AdminStage0Dto.WhoAmI whoami(String userId) {
        return AdminStage0Dto.WhoAmI.builder()
                .userId(userId)
                .isAdmin(adminAllowlistFilter.isAllowed(userId))
                .build();
    }

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/reports — pageable + filter + projection (Codex G)
    // ─────────────────────────────────────────────────────────────────────

    public Page<AdminStage0Dto.ReportRow> listReports(String status, String targetType,
                                                       LocalDateTime createdFrom, LocalDateTime createdTo,
                                                       int page, int size) {
        // 2026-05-29 Codex 사후 Critical 3 — page<0 IllegalArgumentException 가드.
        final int safePage = Math.max(0, page);
        final int safeSize = Math.max(1, Math.min(size, 100));
        Page<Report> reports = reportRepository.findAdminList(
                status, targetType, createdFrom, createdTo,
                PageRequest.of(safePage, safeSize));

        // batch lookup — reporter 닉네임 + target 정보 (N+1 차단).
        List<String> reporterIds = reports.stream().map(Report::getReporterId).distinct().toList();
        Map<String, User> reporterMap = userRepository.findAllById(reporterIds).stream()
                .collect(Collectors.toMap(User::getUserId, u -> u, (a, b) -> a));

        // target USER 닉네임 batch
        List<String> userTargetIds = reports.stream()
                .filter(r -> "USER".equals(r.getTargetType()))
                .map(Report::getTargetId)
                .distinct().toList();
        Map<String, User> userTargetMap = userTargetIds.isEmpty() ? Map.of() :
                userRepository.findAllById(userTargetIds).stream()
                        .collect(Collectors.toMap(User::getUserId, u -> u, (a, b) -> a));

        // target TRADE title batch
        List<String> tradeTargetIds = reports.stream()
                .filter(r -> "TRADE".equals(r.getTargetType()))
                .map(Report::getTargetId)
                .distinct().toList();
        Map<String, TradePost> tradeTargetMap = tradeTargetIds.isEmpty() ? Map.of() :
                tradePostRepository.findAllById(tradeTargetIds).stream()
                        .collect(Collectors.toMap(TradePost::getTradeId, t -> t, (a, b) -> a));

        return reports.map(r -> {
            User reporter = reporterMap.get(r.getReporterId());
            String summary = switch (r.getTargetType()) {
                case "USER" -> {
                    User u = userTargetMap.get(r.getTargetId());
                    yield u != null ? u.getNickname() : null;
                }
                case "TRADE" -> {
                    TradePost t = tradeTargetMap.get(r.getTargetId());
                    yield t != null ? t.getTitle() : null;
                }
                default -> null; // BUY_ORDER / CHAT — Stage 0 에서는 summary 생략
            };
            return AdminStage0Dto.ReportRow.builder()
                    .reportId(r.getReportId())
                    .reporterId(r.getReporterId())
                    .reporterNickname(reporter != null ? reporter.getNickname() : null)
                    .targetType(r.getTargetType())
                    .targetId(r.getTargetId())
                    .targetSummary(summary)
                    .reason(r.getReason())
                    .detail(r.getDetail())
                    .status(r.getStatus())
                    .adminMemo(r.getAdminMemo())
                    .handledBy(r.getHandledBy())
                    .handledAt(r.getHandledAt())
                    .resolutionAction(r.getResolutionAction())
                    .createdAt(r.getCreatedAt())
                    .build();
        });
    }

    public long countByStatus(String status) {
        return reportRepository.countByStatus(status);
    }

    // ─────────────────────────────────────────────────────────────────────
    // PATCH /api/admin/reports/{id}/status
    // ─────────────────────────────────────────────────────────────────────

    @Transactional
    public AdminStage0Dto.ReportRow updateReportStatus(String reportId, String adminUserId,
                                                       AdminStage0Dto.ReportStatusUpdate body) {
        Report report = reportRepository.findById(reportId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "REPORT_NOT_FOUND"));
        String previousState = report.getStatus();
        report.markHandled(body.getStatus(), adminUserId, body.getAdminMemo(), body.getResolutionAction());
        reportRepository.save(report);

        adminActionService.record(adminUserId, "REVIEW_REPORT", "REPORT", reportId,
                reportId, body.getAdminMemo(), previousState, body.getStatus());

        // re-fetch row for response (admin list 와 동일 형태).
        return listReports(null, null, null, null, 0, 1).stream()
                .filter(r -> r.getReportId().equals(reportId))
                .findFirst()
                .orElseGet(() -> AdminStage0Dto.ReportRow.builder()
                        .reportId(reportId).status(body.getStatus()).build());
    }

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/users/search
    // ─────────────────────────────────────────────────────────────────────

    public List<AdminStage0Dto.UserRow> searchUsers(String q, int size) {
        if (q == null || q.isBlank()) return List.of();
        List<User> users = userRepository.searchByNicknameOrEmail(q, PageRequest.of(0, Math.min(size, 100)));
        return users.stream().map(u -> AdminStage0Dto.UserRow.builder()
                .userId(u.getUserId())
                .nickname(u.getNickname())
                .email(u.getDeletedAt() != null ? null : u.getEmail()) // PII safety on deleted
                .suspended(u.isSuspended())
                .suspendedAt(u.getSuspendedAt())
                .suspensionReason(u.getSuspensionReason())
                .deleted(u.getDeletedAt() != null)
                .createdAt(u.getCreatedAt())
                .build()).toList();
    }

    // ─────────────────────────────────────────────────────────────────────
    // POST /api/admin/users/{id}/suspend
    // ─────────────────────────────────────────────────────────────────────

    @Transactional
    public AdminStage0Dto.UserRow suspendUser(String userId, String adminUserId, String reason) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "USER_NOT_FOUND"));

        // admin allowlist 사용자는 정지 면제 (Codex K).
        if (adminAllowlistFilter.isAllowed(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "ADMIN_USER_NOT_SUSPENDABLE");
        }
        if (user.getDeletedAt() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "USER_ALREADY_DELETED");
        }

        String previousState = user.isSuspended() ? "SUSPENDED" : "ACTIVE";
        user.suspend(reason, adminUserId);
        userRepository.save(user);

        adminActionService.record(adminUserId, "SUSPEND", "USER", userId,
                null, reason, previousState, "SUSPENDED");

        return AdminStage0Dto.UserRow.builder()
                .userId(user.getUserId())
                .nickname(user.getNickname())
                .email(user.getEmail())
                .suspended(true)
                .suspendedAt(user.getSuspendedAt())
                .suspensionReason(user.getSuspensionReason())
                .deleted(false)
                .createdAt(user.getCreatedAt())
                .build();
    }

    // ─────────────────────────────────────────────────────────────────────
    // POST /api/admin/users/{id}/unsuspend
    // ─────────────────────────────────────────────────────────────────────

    @Transactional
    public AdminStage0Dto.UserRow unsuspendUser(String userId, String adminUserId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "USER_NOT_FOUND"));
        if (!user.isSuspended()) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "USER_NOT_SUSPENDED");
        }
        user.unsuspend();
        userRepository.save(user);

        adminActionService.record(adminUserId, "UNSUSPEND", "USER", userId,
                null, null, "SUSPENDED", "ACTIVE");

        return AdminStage0Dto.UserRow.builder()
                .userId(user.getUserId())
                .nickname(user.getNickname())
                .email(user.getEmail())
                .suspended(false)
                .deleted(user.getDeletedAt() != null)
                .createdAt(user.getCreatedAt())
                .build();
    }

    // ─────────────────────────────────────────────────────────────────────
    // DELETE /api/admin/trade-posts/{id}
    // ─────────────────────────────────────────────────────────────────────

    @Transactional
    public void adminDeleteTradePost(String tradeId, String adminUserId, String reason) {
        TradePost post = tradePostRepository.findById(tradeId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "TRADE_NOT_FOUND"));

        // idempotency 가드 (Codex J) — 이미 DELETED면 중복 SYSTEM fan-out 차단.
        if ("DELETED".equals(post.getStatus())) {
            // audit 만 기록 (재시도 추적).
            adminActionService.record(adminUserId, "DELETE_TRADE", "TRADE", tradeId,
                    null, reason, "DELETED", "DELETED");
            return;
        }

        String previousState = post.getStatus();
        post.markDeleted();
        tradePostRepository.save(post);

        // 채팅방 양쪽 사용자에게 SYSTEM 메시지 fan-out (기존 패턴).
        chatService.broadcastTradeStatusChanged(tradeId, "DELETED");

        adminActionService.record(adminUserId, "DELETE_TRADE", "TRADE", tradeId,
                null, reason, previousState, "DELETED");
    }
}
