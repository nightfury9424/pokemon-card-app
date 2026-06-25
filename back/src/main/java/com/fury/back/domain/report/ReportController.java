package com.fury.back.domain.report;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.domain.board.BoardPermissions;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.chat.ChatRoom;
import com.fury.back.domain.chat.ChatRoomRepository;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.util.StringUtils;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.web.bind.annotation.*;

import java.util.Map;
import java.util.Set;

@Tag(name = "Report", description = "신고")
@RestController
@RequestMapping("/api/reports")
@RequiredArgsConstructor
public class ReportController {

    private static final Set<String> VALID_TYPES =
            Set.of("TRADE", "USER", "BUY_ORDER", "CHAT", "BOARD_POST", "BOARD_COMMENT");
    private static final Set<String> VALID_REASONS = Set.of(
            "FRAUD", "FAKE", "ABUSIVE_PRICE", "INSULT", "SPAM", "OTHER");

    private final ReportRepository reportRepository;
    private final JwtUtil jwtUtil;
    private final ChatRoomRepository chatRoomRepository;
    private final TradePostRepository tradePostRepository;
    private final BoardPostRepository boardPostRepository;
    private final BoardCommentRepository boardCommentRepository;
    private final ReportService reportService;
    private final AdminAuthorizationService adminAuthorizationService;

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
        // ★기타(OTHER) 사유는 직접 입력 필수 — detail 이 null/공백뿐이면 거부(Front 우회 요청도 서버에서 차단).
        if ("OTHER".equals(reason) && (detail == null || detail.isBlank())) {
            return ReturnData.badRequest("기타 사유는 상세 내용을 입력해야 합니다.");
        }

        // 신고 대상 사용자 해석 (1회 제한 + 자동 차단 공용).
        String targetUserId = resolveBlockTarget(targetType, targetId, reporterId);
        // ★자동차단 적용 여부 — 운영팀 대상(공식글 타입 OR 운영팀 작성자, 자유글 포함)은 자동차단 금지(신고만). 그 외는 기존대로.
        boolean autoBlock = resolveAutoBlock(targetType, targetId, reporterId);

        // ★중복 신고 가드 — 게시판은 글/댓글 단위(reporter+type+id), 그 외는 사용자 단위(기존 정책 보존). DB partial unique 와 일치.
        boolean isBoard = "BOARD_POST".equals(targetType) || "BOARD_COMMENT".equals(targetType);
        if (isBoard) {
            // 게시판: 같은 작성자의 다른 글·댓글은 각각 신고 가능, 같은 글/댓글 재신고만 차단.
            if (reportRepository.existsByReporterIdAndTargetTypeAndTargetId(reporterId, targetType, targetId)) {
                return ReturnData.badRequest("BOARD_COMMENT".equals(targetType)
                        ? "이미 신고한 댓글입니다." : "이미 신고한 게시글입니다.");
            }
        } else if (targetUserId != null && !targetUserId.equals(reporterId)) {
            // USER/TRADE/CHAT: 같은 사용자 1회 제한(차단 풀고 재신고 방지) — 기존 정책 그대로.
            if (reportRepository.existsByReporterIdAndTargetUserId(reporterId, targetUserId)) {
                return ReturnData.badRequest("이미 신고한 사용자입니다.");
            }
        } else {
            // 대상 유저 해석 불가(BUY_ORDER 등): 기존 PENDING per-target 가드 유지.
            long existing = reportRepository.countByReporterIdAndTargetTypeAndTargetIdAndStatus(
                    reporterId, targetType, targetId, "PENDING");
            if (existing > 0) {
                return ReturnData.badRequest("이미 신고하신 항목입니다. 검토 중이에요.");
            }
        }

        // ★snapshot 생성 + 신고 저장 + 자동 차단을 하나의 서비스 트랜잭션으로 원자 처리(부분성공 방지).
        //   board 대상이 미존재/삭제면 snapshot 불가 → BAD_REQUEST. authorId 무관하게 콘텐츠 있으면 신고 가능
        //   (dedup/자동차단만 targetUserId 있을 때).
        final String reportId;
        try {
            reportId = reportService.create(reporterId, targetType, targetId, reason, detail, targetUserId, autoBlock);
        } catch (ResponseStatusException e) {
            // snapshot 불가(미존재/삭제) + block 경쟁 중복 = service 가 BAD_REQUEST 로 변환. 400 만 매핑.
            if (e.getStatusCode().value() == 400) {
                return ReturnData.badRequest(e.getReason());
            }
            throw e; // 400 외 status·기타 DB 오류(DataIntegrityViolation 등)는 의미 유실 없이 전파(5xx)
        }
        return ReturnData.success(Map.of("reportId", reportId));
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
            // 게시판: 글/댓글 작성자 = 제재·dedup·자동차단 대상. 미삭제만(삭제글 신고 불가).
            case "BOARD_POST" -> boardPostRepository.findById(targetId)
                    .filter(p -> p.getDeletedAt() == null)
                    .map(BoardPost::getAuthorId).orElse(null);
            case "BOARD_COMMENT" -> boardCommentRepository.findById(targetId)
                    .filter(c -> c.getDeletedAt() == null)
                    .map(BoardComment::getAuthorId).orElse(null);
            default -> null; // BUY_ORDER 등
        };
    }

    /** 자동차단 적용 여부 — ★공통 판정(BoardPermissions.canBlock*Author) 하나만 사용. 운영팀(공식글 타입 OR
     *  운영팀 작성자·자유글 포함, 운영팀 댓글)이면 false(신고만 생성, 차단 row 0). 그 외(거래/사용자/채팅, 일반 글·댓글)는 true.
     *  대상 미존재면 false(어차피 신고 거부). */
    private boolean resolveAutoBlock(String targetType, String targetId, String reporterId) {
        return switch (targetType) {
            case "BOARD_POST" -> boardPostRepository.findById(targetId)
                    .map(p -> BoardPermissions.canBlockPostAuthor(
                            reporterId, p.getAuthorId(), p.getType(),
                            adminAuthorizationService.isAdmin(p.getAuthorId())))
                    .orElse(false);
            case "BOARD_COMMENT" -> boardCommentRepository.findById(targetId)
                    .map(c -> BoardPermissions.canBlockCommentAuthor(
                            reporterId, c.getAuthorId(), c.isAdmin(),
                            adminAuthorizationService.isAdmin(c.getAuthorId())))
                    .orElse(false);
            default -> true; // TRADE/USER/CHAT = 기존 자동차단 유지
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
