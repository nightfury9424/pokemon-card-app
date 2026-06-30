package com.fury.back.domain.admin;

import com.fury.back.auth.AdminAllowlistFilter;
import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.domain.board.BoardAdminService;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.board.BoardTaxonomy;
import com.fury.back.domain.board.dto.PostModerationRequest;
import com.fury.back.domain.chat.ChatService;
import com.fury.back.domain.report.Report;
import com.fury.back.domain.report.ReportRepository;
import com.fury.back.domain.report.ReportedSnapshot;
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
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
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
    private final UserWarningRepository userWarningRepository;
    private final com.fury.back.domain.inquiry.InquiryRepository inquiryRepository;
    private final AdminActionRepository adminActionRepository;
    private final BoardPostRepository boardPostRepository;
    private final com.fury.back.domain.board.BoardPostImageRepository boardPostImageRepository;
    private final BoardCommentRepository boardCommentRepository;
    private final BoardAdminService boardAdminService;
    private final AdminAuthorizationService adminAuthorizationService;

    /** 활성 경고 누적이 이 수치 도달 시 자동 정지. (신고 처리 정책) */
    @org.springframework.beans.factory.annotation.Value("${app.moderation.warning-threshold:3}")
    private int warningThreshold;

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/whoami
    // ─────────────────────────────────────────────────────────────────────

    public AdminStage0Dto.WhoAmI whoami(String userId) {
        // 2026-05-29 P-1: nickname/email lookup — 사이드바 footer 하드코딩 "관리자/admin" 제거용.
        // 본 endpoint는 filter 통과한 admin 만 도달 → 본인 user row 1건 조회 부담 미미.
        User user = userRepository.findById(userId).orElse(null);
        return AdminStage0Dto.WhoAmI.builder()
                .userId(userId)
                .isAdmin(adminAllowlistFilter.isAllowed(userId))
                .nickname(user != null ? user.getNickname() : null)
                .email(user != null ? user.getEmail() : null)
                .build();
    }

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/admin-actions — 운영(감사) 로그 뷰어 (2026-06-07 관측성 Phase 1)
    //   admin_actions 는 기록만 되고 조회 UI 가 없었음. actionType/targetType 선택 필터 + 최신순 페이징.
    // ─────────────────────────────────────────────────────────────────────
    public Page<AdminStage0Dto.AdminActionRow> listAdminActions(String actionType, String targetType,
                                                                int page, int size) {
        final int safePage = Math.max(0, page);
        final int safeSize = Math.min(Math.max(1, size), 100);
        final String at = (actionType == null || actionType.isBlank()) ? null : actionType;
        final String tt = (targetType == null || targetType.isBlank()) ? null : targetType;

        Page<AdminAction> result = adminActionRepository.findFiltered(
                at, tt, PageRequest.of(safePage, safeSize));

        // admin nickname batch lookup — 액션 수행자는 대개 소수라 페이지당 distinct 조회 부담 미미.
        Map<String, String> nickMap = new HashMap<>();
        result.getContent().stream()
                .map(AdminAction::getAdminUserId)
                .distinct()
                .forEach(id -> userRepository.findById(id)
                        .ifPresent(u -> nickMap.put(id, u.getNickname())));

        return result.map(a -> AdminStage0Dto.AdminActionRow.builder()
                .actionId(a.getActionId())
                .adminUserId(a.getAdminUserId())
                .adminNickname(nickMap.get(a.getAdminUserId()))
                .actionType(a.getActionType())
                .targetType(a.getTargetType())
                .targetId(a.getTargetId())
                .reportId(a.getReportId())
                .memo(a.getMemo())
                .previousState(a.getPreviousState())
                .newState(a.getNewState())
                .createdAt(a.getCreatedAt())
                .build());
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

        // target BOARD_POST / BOARD_COMMENT batch (N+1 차단).
        List<String> postTargetIds = reports.stream()
                .filter(r -> "BOARD_POST".equals(r.getTargetType()))
                .map(Report::getTargetId).distinct().toList();
        Map<String, BoardPost> postTargetMap = postTargetIds.isEmpty() ? Map.of() :
                boardPostRepository.findAllById(postTargetIds).stream()
                        .collect(Collectors.toMap(BoardPost::getPostId, p -> p, (a, b) -> a));
        List<String> commentTargetIds = reports.stream()
                .filter(r -> "BOARD_COMMENT".equals(r.getTargetType()))
                .map(Report::getTargetId).distinct().toList();
        Map<String, BoardComment> commentTargetMap = commentTargetIds.isEmpty() ? Map.of() :
                boardCommentRepository.findAllById(commentTargetIds).stream()
                        .collect(Collectors.toMap(BoardComment::getCommentId, c -> c, (a, b) -> a));

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
                case "BOARD_POST" -> {
                    BoardPost p = postTargetMap.get(r.getTargetId());
                    yield p == null ? null : truncate(p.getTitle() + " — " + p.getContent(), 80);
                }
                case "BOARD_COMMENT" -> {
                    BoardComment c = commentTargetMap.get(r.getTargetId());
                    yield c == null ? null : truncate(c.getContent(), 80);
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

    /** 뱃지/대시보드 — 미처리(OPEN) 고객 문의 수(정지 이의신청 제외). */
    public long countPendingInquiries() {
        return inquiryRepository.countByStatusAndCategoryNot("OPEN", "SUSPENSION_APPEAL");
    }

    /** 뱃지/대시보드 — 미처리(OPEN) 정지 이의신청 수. */
    public long countPendingAppeals() {
        return inquiryRepository.countByStatusAndCategory("OPEN", "SUSPENSION_APPEAL");
    }

    /** 관리자 목록 요약용 안전 축약 — null/공백/길이 방어(목록 전체 실패 방지). */
    private static String truncate(String s, int max) {
        if (s == null) return null;
        String t = s.replaceAll("\\s+", " ").trim();
        if (t.isEmpty()) return null;
        return t.length() <= max ? t : t.substring(0, max) + "…";
    }

    // ─────────────────────────────────────────────────────────────────────
    // GET /api/admin/reports/{id}/target-context — 게시판 신고 원문·문맥(파괴적 조치 전 확인용)
    //   ★일반 BoardService 의 ACTIVE·미삭제 필터 재사용 안 함 — 숨김/삭제 콘텐츠도 관리자에게 반환.
    // ─────────────────────────────────────────────────────────────────────
    public AdminStage0Dto.TargetContext getTargetContext(String reportId, String adminUserId) {
        requireAdminContext(adminUserId); // 필터(웹) + 서비스 이중 검증
        Report report = reportRepository.findById(reportId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "REPORT_NOT_FOUND"));
        return switch (report.getTargetType()) {
            case "BOARD_POST" -> postContext(report);
            case "BOARD_COMMENT" -> commentContext(report);
            default -> throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "게시판 신고만 원문 조회를 지원합니다.");
        };
    }

    private void requireAdminContext(String userId) {
        if (adminAuthorizationService.isEnforced() && !adminAuthorizationService.isAdmin(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "관리자 권한이 필요합니다.");
        }
    }

    private AdminStage0Dto.TargetContext postContext(Report report) {
        BoardPost p = boardPostRepository.findById(report.getTargetId()).orElse(null);
        if (p == null) return unavailable(report); // 물리 삭제/미존재
        Set<String> ids = new HashSet<>();
        ids.add(p.getAuthorId()); // ★null 허용(HashSet) — 공식글/레거시 authorId null 가능. Set.of(null) NPE 회피.
        ReportedSnapshot snap = report.getReportedSnapshot();
        String snapStatus = snapshotStatus(snap);
        boolean snapOk = "AVAILABLE".equals(snapStatus);
        return AdminStage0Dto.TargetContext.builder()
                .reportId(report.getReportId()).targetType("BOARD_POST").targetId(report.getTargetId())
                .available(true)
                .post(postView(p, nicknameMap(ids)))
                .snapshotStatus(snapStatus)
                .snapshotAvailable(snapOk)
                .changedSinceReport(snapOk && postChanged(snap, p))
                .reportedSnapshot(snapOk ? sanitizeSnapshot(snap) : null)
                .snapshotImageCount(snapOk ? snap.imageCount() : 0)
                .snapshotImageUrls(snapOk ? proxyUrls(snap.imageKeys()) : java.util.List.of())
                .currentImageUrls(currentImageUrls(p.getPostId()))
                .build();
    }

    /** raw storage key → secure proxy URL(관리자 화면 노출용, raw 키 미노출). */
    private java.util.List<String> proxyUrls(java.util.List<String> keys) {
        if (keys == null) return java.util.List.of();
        return keys.stream().map(com.fury.back.storage.StorageKeyUrls::toProxyUrl).toList();
    }

    private java.util.List<String> currentImageUrls(String postId) {
        return boardPostImageRepository.findByPostIdOrderBySortOrderAsc(postId).stream()
                .map(i -> com.fury.back.storage.StorageKeyUrls.toProxyUrl(i.getStorageKey())).toList();
    }

    /** 관리자 응답용 snapshot 사본 — ★raw imageKeys 제거(proxy URL 은 snapshotImageUrls 로 별도 전달). */
    private ReportedSnapshot sanitizeSnapshot(ReportedSnapshot s) {
        if (s == null) return null;
        return new ReportedSnapshot(s.version(), s.targetType(), s.title(), s.content(), s.authorLabel(),
                s.targetCreatedAt(), s.targetUpdatedAt(), s.imageCount(), null,
                s.postTitle(), s.targetCommentId(), s.topCommentId(), s.comments());
    }

    private AdminStage0Dto.TargetContext commentContext(Report report) {
        BoardComment c = boardCommentRepository.findById(report.getTargetId()).orElse(null);
        if (c == null) return unavailable(report);
        BoardPost p = boardPostRepository.findById(c.getPostId()).orElse(null);
        // 대댓글 신고면 부모(최상위)를, 최상위 댓글 신고면 자기 자신을 thread 루트로.
        String topId = c.getParentCommentId() != null ? c.getParentCommentId() : c.getCommentId();
        // 1 query: 게시글 전체 댓글 조회 → 해당 최상위 thread(최상위 + 그 대댓글)만 응답(unrelated 제외).
        List<BoardComment> thread = boardCommentRepository.findByPostIdOrderByCreatedAtAsc(c.getPostId()).stream()
                .filter(x -> x.getCommentId().equals(topId) || topId.equals(x.getParentCommentId()))
                .toList();
        Set<String> authorIds = new HashSet<>();
        thread.forEach(x -> authorIds.add(x.getAuthorId()));
        if (p != null) authorIds.add(p.getAuthorId());
        Map<String, String> nicks = nicknameMap(authorIds);
        List<AdminStage0Dto.BoardCommentView> views = thread.stream()
                .map(x -> commentView(x, nicks, report.getTargetId())).toList();
        ReportedSnapshot snap = report.getReportedSnapshot();
        String snapStatus = snapshotStatus(snap);
        boolean snapOk = "AVAILABLE".equals(snapStatus);
        return AdminStage0Dto.TargetContext.builder()
                .reportId(report.getReportId()).targetType("BOARD_COMMENT").targetId(report.getTargetId())
                .available(true)
                .post(p == null ? null : postView(p, nicks)) // 게시글이 물리삭제돼도 댓글 thread 는 노출
                .thread(AdminStage0Dto.BoardCommentThread.builder()
                        .targetCommentId(report.getTargetId()).topCommentId(topId).comments(views).build())
                .snapshotStatus(snapStatus)
                .snapshotAvailable(snapOk)
                .changedSinceReport(snapOk && commentChanged(snap, thread, p))
                .reportedSnapshot(snapOk ? sanitizeSnapshot(snap) : null) // 댓글엔 이미지 없음(키도 null)
                .build();
    }

    private AdminStage0Dto.TargetContext unavailable(Report report) {
        ReportedSnapshot snap = report.getReportedSnapshot();
        String snapStatus = snapshotStatus(snap);
        boolean snapOk = "AVAILABLE".equals(snapStatus);
        return AdminStage0Dto.TargetContext.builder()
                .reportId(report.getReportId()).targetType(report.getTargetType())
                .targetId(report.getTargetId()).available(false)
                .snapshotStatus(snapStatus).snapshotAvailable(snapOk)
                .changedSinceReport(false).reportedSnapshot(snapOk ? snap : null)
                .build();
    }

    // 신고 당시 snapshot 상태 — null(=정상·기존신고)만 LEGACY, 미지원 버전·필수누락을 같은 null 로 합치지 않음.
    private static String snapshotStatus(ReportedSnapshot snap) {
        if (snap == null) return "LEGACY_NOT_CAPTURED";
        if (snap.version() != ReportedSnapshot.CURRENT_VERSION) return "UNSUPPORTED_VERSION";
        if (!snap.hasRequiredFields()) return "INVALID";
        return "AVAILABLE";
    }

    // 신고 당시 snapshot vs 현재 내용 비교(snapshot 없으면 false=비교 불가).
    private static boolean postChanged(ReportedSnapshot snap, BoardPost current) {
        if (snap == null || current == null) return false;
        return !java.util.Objects.equals(snap.title(), current.getTitle())
                || !java.util.Objects.equals(snap.content(), current.getContent());
    }

    // 댓글 신고 변화 감지 = 부모 게시글 제목(snapshot 보존분) + thread 구성/본문.
    private static boolean commentChanged(ReportedSnapshot snap, List<BoardComment> current, BoardPost currentPost) {
        if (snap == null) return false;
        if (currentPost != null && !java.util.Objects.equals(snap.postTitle(), currentPost.getTitle())) {
            return true; // 부모 게시글 제목 신고 후 수정
        }
        return commentThreadChanged(snap, current);
    }

    private static boolean commentThreadChanged(ReportedSnapshot snap, List<BoardComment> current) {
        if (snap == null) return false;
        List<ReportedSnapshot.SnapshotComment> snapList =
                snap.comments() == null ? List.of() : snap.comments();
        if (snapList.size() != current.size()) return true; // 댓글 추가/삭제
        Map<String, BoardComment> cur = current.stream()
                .collect(Collectors.toMap(BoardComment::getCommentId, x -> x, (a, b) -> a));
        for (ReportedSnapshot.SnapshotComment s : snapList) {
            BoardComment c = cur.get(s.commentId());
            if (c == null || !java.util.Objects.equals(s.content(), c.getContent())) return true;
        }
        return false;
    }

    private AdminStage0Dto.BoardPostView postView(BoardPost p, Map<String, String> nicks) {
        return AdminStage0Dto.BoardPostView.builder()
                .postId(p.getPostId()).type(p.getType()).title(p.getTitle()).content(p.getContent())
                .authorLabel(authorLabel(p.getType(), p.getAuthorId(), nicks))
                .status(p.getStatus()).hidden("HIDDEN".equals(p.getStatus())).deleted(p.getDeletedAt() != null)
                .createdAt(p.getCreatedAt())
                .build();
    }

    private AdminStage0Dto.BoardCommentView commentView(BoardComment c, Map<String, String> nicks, String targetId) {
        return AdminStage0Dto.BoardCommentView.builder()
                .commentId(c.getCommentId()).parentCommentId(c.getParentCommentId())
                .authorLabel(userLabel(c.getAuthorId(), nicks))
                .content(c.getContent()).deleted(c.getDeletedAt() != null)
                .target(c.getCommentId().equals(targetId)) // 신고된 댓글 강조
                .createdAt(c.getCreatedAt())
                .build();
    }

    private String authorLabel(String type, String authorId, Map<String, String> nicks) {
        if (BoardTaxonomy.isAdminType(type)) return "운영팀"; // 공식글 표시명(조회 없이)
        if (authorId == null || authorId.isBlank()) return "(알 수 없음)"; // null 키 lookup(Map.of NPE) 회피
        return nicks.getOrDefault(authorId, "(알 수 없음)");
    }

    private String userLabel(String authorId, Map<String, String> nicks) {
        if (authorId == null || authorId.isBlank()) return "(알 수 없음)";
        return nicks.getOrDefault(authorId, "(알 수 없음)");
    }

    private Map<String, String> nicknameMap(Set<String> userIds) {
        // ★null/blank id 제거 — findAllById 에 null 전달 시 오쿼리/예외 방지(공식글·레거시·삭제 데이터 대비).
        Set<String> clean = userIds.stream()
                .filter(id -> id != null && !id.isBlank())
                .collect(Collectors.toSet());
        if (clean.isEmpty()) return Map.of();
        Map<String, String> m = new HashMap<>();
        userRepository.findAllById(clean).forEach(u -> m.put(u.getUserId(), u.getNickname())); // batch(N+1 차단)
        return m;
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

        // ★resolutionAction 실제 실행 — 이전엔 라벨만 저장되고 정작 정지/삭제가 안 돌던 구멍(P0).
        //   SUSPEND_USER/WARN_USER → 대상 유저 / DELETE_TRADE → 대상 거래글 / NONE·DISMISS → 상태만.
        final String act = body.getResolutionAction();
        if ("SUSPEND_USER".equals(act) && report.getTargetUserId() != null) {
            suspendUser(report.getTargetUserId(), adminUserId, "신고 처리: " + report.getReason());
        } else if ("WARN_USER".equals(act) && report.getTargetUserId() != null) {
            warnUser(report.getTargetUserId(), adminUserId, "신고 처리: " + report.getReason(), reportId);
        } else if ("DELETE_TRADE".equals(act) && "TRADE".equals(report.getTargetType())) {
            adminDeleteTradePost(report.getTargetId(), adminUserId, "신고 처리: " + report.getReason());
        } else if ("HIDE_BOARD_POST".equals(act) && "BOARD_POST".equals(report.getTargetType())) {
            // 기존 BoardAdminService 재사용(중복 구현 X) — 같은 트랜잭션서 모더레이션 + 자체 감사로그.
            boardAdminService.moderatePost(adminUserId, report.getTargetId(), new PostModerationRequest("HIDE"));
        } else if ("DELETE_BOARD_POST".equals(act) && "BOARD_POST".equals(report.getTargetType())) {
            boardAdminService.deletePost(adminUserId, report.getTargetId());
        } else if ("DELETE_BOARD_COMMENT".equals(act) && "BOARD_COMMENT".equals(report.getTargetType())) {
            boardAdminService.deleteComment(adminUserId, report.getTargetId());
        }

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
    // POST /api/admin/users/{id}/warn — 경고 발급 (누적 임계치 도달 시 자동 정지)
    // ─────────────────────────────────────────────────────────────────────

    @Transactional
    public AdminStage0Dto.UserRow warnUser(String userId, String adminUserId, String reason, String reportId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "USER_NOT_FOUND"));
        if (adminAllowlistFilter.isAllowed(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "ADMIN_USER_NOT_WARNABLE");
        }
        if (user.getDeletedAt() != null) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "USER_ALREADY_DELETED");
        }
        String safeReason = (reason == null || reason.isBlank()) ? "(사유 없음)" : reason.trim();
        userWarningRepository.save(UserWarning.builder()
                .warningId(com.fury.back.common.IdGenerator.generate())
                .userId(userId)
                .reason(safeReason)
                .reportId(reportId)
                .issuedBy(adminUserId)
                .build());
        long count = userWarningRepository.countByUserIdAndRevokedAtIsNull(userId);
        adminActionService.record(adminUserId, "WARN", "USER", userId,
                null, "경고 " + count + "회: " + safeReason, null, null);

        boolean autoSuspended = false;
        // 임계치 도달 + 아직 정지 안 됨 → 자동 정지.
        if (count >= warningThreshold && !user.isSuspended()) {
            user.suspend("경고 " + count + "회 누적 자동 정지", adminUserId);
            userRepository.save(user);
            adminActionService.record(adminUserId, "AUTO_SUSPEND", "USER", userId,
                    null, "경고 임계치(" + warningThreshold + ") 도달", "ACTIVE", "SUSPENDED");
            autoSuspended = true;
        }
        return AdminStage0Dto.UserRow.builder()
                .userId(user.getUserId())
                .nickname(user.getNickname())
                .email(user.getEmail())
                .suspended(user.isSuspended())
                .suspendedAt(user.getSuspendedAt())
                .suspensionReason(user.getSuspensionReason())
                .deleted(user.getDeletedAt() != null)
                .createdAt(user.getCreatedAt())
                .warningCount(count)
                .autoSuspended(autoSuspended)
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

        // 해제 = 이의신청 해결 → 해당 유저의 OPEN 정지 이의신청 자동 종료(인박스 정리 + 재정지 시 재신청 가능).
        var openAppeals = inquiryRepository.findByUserIdAndCategoryAndStatus(
                userId, "SUSPENSION_APPEAL", "OPEN");
        for (var appeal : openAppeals) {
            appeal.markClosed();
        }
        if (!openAppeals.isEmpty()) {
            inquiryRepository.saveAll(openAppeals);
        }

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
