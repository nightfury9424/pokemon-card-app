package com.fury.back.domain.report;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.chat.ChatRoom;
import com.fury.back.domain.chat.ChatRoomRepository;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
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
    private final BlockRepository blockRepository;
    private final ChatRoomRepository chatRoomRepository;
    private final TradePostRepository tradePostRepository;

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

        // 신고 대상 사용자 해석 (1회 제한 + 자동 차단 공용).
        String targetUserId = resolveBlockTarget(targetType, targetId, reporterId);

        // 1회 제한 — 같은 사용자를 이미 신고했으면 차단 (차단 풀고 재신고 방지).
        if (targetUserId != null && !targetUserId.equals(reporterId)
                && reportRepository.existsByReporterIdAndTargetUserId(reporterId, targetUserId)) {
            return ReturnData.badRequest("이미 신고한 사용자입니다.");
        }
        // 대상 유저 해석 불가(BUY_ORDER 등) 시 기존 PENDING 중복 가드 유지.
        if (targetUserId == null) {
            long existing = reportRepository.countByReporterIdAndTargetTypeAndTargetIdAndStatus(
                    reporterId, targetType, targetId, "PENDING");
            if (existing > 0) {
                return ReturnData.badRequest("이미 신고하신 항목입니다. 검토 중이에요.");
            }
        }

        Report report = Report.builder()
                .reportId(IdGenerator.generate())
                .reporterId(reporterId)
                .targetType(targetType)
                .targetId(targetId)
                .targetUserId(targetUserId)
                .reason(reason)
                .detail(detail)
                .status("PENDING")
                .build();
        Report saved = reportRepository.save(report);

        // 신고 시 대상 사용자 자동 차단. 차단 실패해도 신고는 접수.
        try {
            if (targetUserId != null && !targetUserId.equals(reporterId)
                    && blockRepository.findByBlockerIdAndBlockedId(reporterId, targetUserId).isEmpty()) {
                blockRepository.save(Block.builder()
                        .blockId(IdGenerator.generate())
                        .blockerId(reporterId)
                        .blockedId(targetUserId)
                        .build());
            }
        } catch (Exception ignored) {
            // 차단 실패는 무시 — 신고 접수가 우선.
        }

        return ReturnData.success(Map.of("reportId", saved.getReportId()));
    }

    /** 신고 대상 → 차단할 사용자 id. USER=대상, TRADE=판매자, CHAT=상대(나 아닌 참가자). */
    private String resolveBlockTarget(String targetType, String targetId, String reporterId) {
        return switch (targetType) {
            case "USER" -> targetId;
            case "TRADE" -> tradePostRepository.findById(targetId)
                    .map(TradePost::getSellerId).orElse(null);
            case "CHAT" -> chatRoomRepository.findById(targetId)
                    .map(r -> reporterId.equals(r.getSellerUserId())
                            ? r.getBuyerUserId() : r.getSellerUserId())
                    .orElse(null);
            default -> null; // BUY_ORDER 등
        };
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
