package com.fury.back.domain.report;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.Set;

@Tag(name = "Report", description = "신고")
@RestController
@RequestMapping("/api/reports")
@RequiredArgsConstructor
public class ReportController {

    private static final Set<String> VALID_TYPES = Set.of("TRADE", "USER", "BUY_ORDER", "CHAT");
    private static final Set<String> VALID_REASONS = Set.of(
            "FRAUD", "FAKE", "ABUSIVE_PRICE", "INSULT", "SPAM", "OTHER");

    private final ReportRepository reportRepository;
    private final JwtUtil jwtUtil;

    @Operation(summary = "신고 등록", description = "거래/사용자/매수호가/채팅 신고")
    @PostMapping
    public ReturnData<Map<String, String>> create(
            HttpServletRequest request,
            @RequestBody Map<String, Object> body) {
        String reporterId = extractUserId(request);
        if (reporterId == null) return ReturnData.fail("F403", "인증이 필요합니다.");

        final Map<String, Object> data;
        if (body.get("data") instanceof Map<?, ?> nested) {
            @SuppressWarnings("unchecked")
            final Map<String, Object> casted = (Map<String, Object>) nested;
            data = casted;
        } else {
            data = body;
        }
        String targetType = String.valueOf(data.get("targetType"));
        String targetId = String.valueOf(data.get("targetId"));
        String reason = String.valueOf(data.get("reason"));
        String detail = data.get("detail") != null ? String.valueOf(data.get("detail")) : null;

        if (!VALID_TYPES.contains(targetType)) {
            return ReturnData.badRequest("targetType은 " + VALID_TYPES + " 중 하나여야 합니다.");
        }
        if (targetId == null || targetId.isBlank()) {
            return ReturnData.badRequest("targetId는 필수입니다.");
        }
        if (!VALID_REASONS.contains(reason)) {
            return ReturnData.badRequest("reason은 " + VALID_REASONS + " 중 하나여야 합니다.");
        }

        // 같은 사용자가 같은 대상에 PENDING 신고 1번 제한 (중복 방지)
        long existing = reportRepository.countByReporterIdAndTargetTypeAndTargetIdAndStatus(
                reporterId, targetType, targetId, "PENDING");
        if (existing > 0) {
            return ReturnData.badRequest("이미 신고하신 항목입니다. 검토 중이에요.");
        }

        Report report = Report.builder()
                .reportId(IdGenerator.generate())
                .reporterId(reporterId)
                .targetType(targetType)
                .targetId(targetId)
                .reason(reason)
                .detail(detail)
                .status("PENDING")
                .build();
        Report saved = reportRepository.save(report);
        return ReturnData.success(Map.of("reportId", saved.getReportId()));
    }

    @Operation(summary = "내 신고 list")
    @GetMapping("/me")
    public ReturnData<java.util.List<Report>> getMine(HttpServletRequest request) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.success(java.util.List.of());
        return ReturnData.success(reportRepository.findByReporterIdOrderByCreatedAtDesc(userId));
    }

    private String extractUserId(HttpServletRequest request) {
        String bearer = request.getHeader("Authorization");
        if (StringUtils.hasText(bearer) && bearer.startsWith("Bearer ")) {
            String token = bearer.substring(7);
            if (jwtUtil.isValid(token)) return jwtUtil.extractUserId(token);
        }
        return null;
    }
}
