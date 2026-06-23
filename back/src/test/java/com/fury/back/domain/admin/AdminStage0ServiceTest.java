package com.fury.back.domain.admin;

import com.fury.back.auth.AdminAllowlistFilter;
import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.domain.board.BoardAdminService;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.board.dto.PostModerationRequest;
import com.fury.back.domain.chat.ChatService;
import com.fury.back.domain.inquiry.InquiryRepository;
import com.fury.back.domain.report.Report;
import com.fury.back.domain.report.ReportRepository;
import com.fury.back.domain.report.ReportedSnapshot;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 게시판 신고 admin 연동 — board targetSummary + resolutionAction(숨김/삭제는 BoardAdminService 재사용,
 *  경고/정지는 기존 targetUserId 흐름 재사용) + 상태·운영로그 + 기존 TRADE 회귀. */
@ExtendWith(MockitoExtension.class)
class AdminStage0ServiceTest {

    @Mock ReportRepository reportRepository;
    @Mock UserRepository userRepository;
    @Mock TradePostRepository tradePostRepository;
    @Mock AdminAllowlistFilter adminAllowlistFilter;
    @Mock AdminActionService adminActionService;
    @Mock ChatService chatService;
    @Mock UserWarningRepository userWarningRepository;
    @Mock InquiryRepository inquiryRepository;
    @Mock AdminActionRepository adminActionRepository;
    @Mock BoardPostRepository boardPostRepository;
    @Mock BoardCommentRepository boardCommentRepository;
    @Mock BoardAdminService boardAdminService;
    @Mock AdminAuthorizationService adminAuthorizationService;
    @InjectMocks AdminStage0Service service;

    @BeforeEach
    void setup() {
        ReflectionTestUtils.setField(service, "warningThreshold", 3);
        lenient().when(userRepository.findAllById(any())).thenReturn(List.of()); // reporter/re-fetch 닉네임
    }

    private AdminStage0Dto.ReportStatusUpdate body(String status, String action, String memo) {
        var b = mock(AdminStage0Dto.ReportStatusUpdate.class);
        lenient().when(b.getStatus()).thenReturn(status);
        lenient().when(b.getResolutionAction()).thenReturn(action);
        lenient().when(b.getAdminMemo()).thenReturn(memo);
        return b;
    }

    private Report report(String type, String targetId, String targetUserId) {
        return Report.builder().reportId("r1").reporterId("reporter").targetType(type)
                .targetId(targetId).targetUserId(targetUserId).reason("INSULT")
                .status("PENDING").createdAt(LocalDateTime.now()).build();
    }

    // ── targetSummary ──
    @Test
    void listReports_boardPost_summary() {
        when(reportRepository.findAdminList(any(), any(), any(), any(), any()))
                .thenReturn(new PageImpl<>(List.of(report("BOARD_POST", "p1", "author1"))));
        when(boardPostRepository.findAllById(any()))
                .thenReturn(List.of(BoardPost.builder().postId("p1").title("제목").content("본문내용").build()));

        var row = service.listReports(null, null, null, null, 0, 20).getContent().get(0);
        assertThat(row.getTargetSummary()).contains("제목").contains("본문내용");
    }

    @Test
    void listReports_boardComment_summary() {
        when(reportRepository.findAdminList(any(), any(), any(), any(), any()))
                .thenReturn(new PageImpl<>(List.of(report("BOARD_COMMENT", "c1", "author2"))));
        when(boardCommentRepository.findAllById(any()))
                .thenReturn(List.of(BoardComment.builder().commentId("c1").authorId("author2").content("댓글본문").build()));

        var row = service.listReports(null, null, null, null, 0, 20).getContent().get(0);
        assertThat(row.getTargetSummary()).contains("댓글본문");
    }

    // ── resolutionAction: board 콘텐츠 조치(BoardAdminService 재사용) ──
    @Test
    void resolution_hideBoardPost_dispatches_and_logs() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", "author1")));
        when(reportRepository.findAdminList(any(), any(), any(), any(), any())).thenReturn(new PageImpl<>(List.of()));

        service.updateReportStatus("r1", "admin1", body("RESOLVED", "HIDE_BOARD_POST", "memo"));

        verify(boardAdminService).moderatePost(eq("admin1"), eq("p1"),
                argThat((PostModerationRequest r) -> "HIDE".equals(r.action())));
        verify(adminActionService).record(eq("admin1"), eq("REVIEW_REPORT"), eq("REPORT"), eq("r1"),
                eq("r1"), eq("memo"), eq("PENDING"), eq("RESOLVED")); // 상태변경 + 운영로그 동일 트랜잭션
    }

    @Test
    void resolution_deleteBoardPost_dispatches() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", "author1")));
        when(reportRepository.findAdminList(any(), any(), any(), any(), any())).thenReturn(new PageImpl<>(List.of()));

        service.updateReportStatus("r1", "admin1", body("RESOLVED", "DELETE_BOARD_POST", null));

        verify(boardAdminService).deletePost("admin1", "p1");
        verify(boardAdminService, never()).deleteComment(any(), any());
    }

    @Test
    void resolution_deleteBoardComment_dispatches() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "c1", "author2")));
        when(reportRepository.findAdminList(any(), any(), any(), any(), any())).thenReturn(new PageImpl<>(List.of()));

        service.updateReportStatus("r1", "admin1", body("RESOLVED", "DELETE_BOARD_COMMENT", null));

        verify(boardAdminService).deleteComment("admin1", "c1");
    }

    // ── resolutionAction: 작성자 제재(기존 targetUserId 흐름 재사용) ──
    @Test
    void resolution_suspendUser_fromBoardReport_reuses_existing() {
        User author = User.builder().userId("author1").build();
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", "author1")));
        when(reportRepository.findAdminList(any(), any(), any(), any(), any())).thenReturn(new PageImpl<>(List.of()));
        when(userRepository.findById("author1")).thenReturn(Optional.of(author));
        when(adminAllowlistFilter.isAllowed("author1")).thenReturn(false);

        service.updateReportStatus("r1", "admin1", body("RESOLVED", "SUSPEND_USER", null));

        verify(userRepository).save(author);
        assertThat(author.isSuspended()).isTrue(); // 실제 계정 정지 적용
        verify(adminActionService).record(eq("admin1"), eq("SUSPEND"), eq("USER"), eq("author1"),
                any(), any(), any(), eq("SUSPENDED"));
    }

    @Test
    void resolution_warnUser_fromBoardReport_reuses_existing() {
        User author = User.builder().userId("author1").build();
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "c1", "author2")));
        when(reportRepository.findAdminList(any(), any(), any(), any(), any())).thenReturn(new PageImpl<>(List.of()));
        when(userRepository.findById("author2")).thenReturn(Optional.of(author));
        when(adminAllowlistFilter.isAllowed("author2")).thenReturn(false);
        when(userWarningRepository.countByUserIdAndRevokedAtIsNull("author2")).thenReturn(1L); // 임계 미만

        service.updateReportStatus("r1", "admin1", body("RESOLVED", "WARN_USER", null));

        verify(userWarningRepository).save(any(UserWarning.class));
        verify(adminActionService).record(eq("admin1"), eq("WARN"), eq("USER"), eq("author2"),
                any(), any(), any(), any());
    }

    // ── 기존 TRADE 회귀 ──
    @Test
    void resolution_deleteTrade_regression() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("TRADE", "t1", "seller1")));
        when(reportRepository.findAdminList(any(), any(), any(), any(), any())).thenReturn(new PageImpl<>(List.of()));
        when(tradePostRepository.findById("t1"))
                .thenReturn(Optional.of(TradePost.builder().tradeId("t1").sellerId("seller1").status("ACTIVE").build()));

        service.updateReportStatus("r1", "admin1", body("RESOLVED", "DELETE_TRADE", null));

        verify(tradePostRepository).save(argThat((TradePost t) -> "DELETED".equals(t.getStatus())));
        verify(chatService).broadcastTradeStatusChanged("t1", "DELETED");
        verify(boardAdminService, never()).deletePost(any(), any()); // board 분기 미발동
    }

    // ── 원문·문맥 조회(target-context): 숨김/삭제 포함·thread 한정·강조·미존재·권한 ──
    private BoardPost post(String id, String author, String status, java.time.LocalDateTime deleted) {
        return BoardPost.builder().postId(id).type("free").title("제목전문").content("본문전문")
                .authorId(author).status(status).deletedAt(deleted)
                .createdAt(java.time.LocalDateTime.now()).build();
    }

    private BoardComment cmt(String id, String parent, String author, String content, java.time.LocalDateTime deleted) {
        return BoardComment.builder().commentId(id).postId("p1").parentCommentId(parent).authorId(author)
                .content(content).deletedAt(deleted).createdAt(java.time.LocalDateTime.now()).build();
    }

    @Test void targetContext_boardPost_fullContent() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", "a1")));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a1", "ACTIVE", null)));
        var ctx = service.getTargetContext("r1", "admin1");
        assertThat(ctx.isAvailable()).isTrue();
        assertThat(ctx.getPost().getTitle()).isEqualTo("제목전문");
        assertThat(ctx.getPost().getContent()).isEqualTo("본문전문"); // 80자 축약 아닌 전문
        assertThat(ctx.getPost().isHidden()).isFalse();
        assertThat(ctx.getThread()).isNull();
    }

    @Test void targetContext_hiddenPost_returned() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", "a1")));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a1", "HIDDEN", null)));
        assertThat(service.getTargetContext("r1", "admin1").getPost().isHidden()).isTrue(); // ACTIVE 필터 안 씀
    }

    @Test void targetContext_deletedPost_returned() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", "a1")));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a1", "ACTIVE", java.time.LocalDateTime.now())));
        assertThat(service.getTargetContext("r1", "admin1").getPost().isDeleted()).isTrue();
    }

    @Test void targetContext_postMissing_unavailable() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "gone", "a1")));
        when(boardPostRepository.findById("gone")).thenReturn(Optional.empty());
        var ctx = service.getTargetContext("r1", "admin1");
        assertThat(ctx.isAvailable()).isFalse();
        assertThat(ctx.getPost()).isNull();
    }

    @Test void targetContext_replyComment_topThreadOnly_targetHighlighted() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "cR", "a2")));
        var cTop = cmt("cTop", null, "a3", "최상위댓글", null);
        var cR = cmt("cR", "cTop", "a2", "신고된대댓글", null);
        var cOther = cmt("cOther", null, "a4", "무관댓글", null);
        when(boardCommentRepository.findById("cR")).thenReturn(Optional.of(cR));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a3", "ACTIVE", null)));
        when(boardCommentRepository.findByPostIdOrderByCreatedAtAsc("p1")).thenReturn(List.of(cTop, cR, cOther));
        var ctx = service.getTargetContext("r1", "admin1");
        assertThat(ctx.getPost().getTitle()).isEqualTo("제목전문"); // 원문 게시글
        assertThat(ctx.getThread().getTopCommentId()).isEqualTo("cTop");
        assertThat(ctx.getThread().getTargetCommentId()).isEqualTo("cR");
        var ids = ctx.getThread().getComments().stream().map(AdminStage0Dto.BoardCommentView::getCommentId).toList();
        assertThat(ids).containsExactlyInAnyOrder("cTop", "cR"); // 무관 댓글 cOther 제외
        var target = ctx.getThread().getComments().stream().filter(AdminStage0Dto.BoardCommentView::isTarget).toList();
        assertThat(target).hasSize(1);
        assertThat(target.get(0).getCommentId()).isEqualTo("cR"); // 신고된 댓글 강조
    }

    @Test void targetContext_topComment_threadSelfPlusReplies() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "cTop", "a3")));
        var cTop = cmt("cTop", null, "a3", "최상위", null);
        var cReply = cmt("cReply", "cTop", "a2", "대댓글", null);
        when(boardCommentRepository.findById("cTop")).thenReturn(Optional.of(cTop));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a3", "ACTIVE", null)));
        when(boardCommentRepository.findByPostIdOrderByCreatedAtAsc("p1")).thenReturn(List.of(cTop, cReply));
        var ctx = service.getTargetContext("r1", "admin1");
        assertThat(ctx.getThread().getTopCommentId()).isEqualTo("cTop");
        var ids = ctx.getThread().getComments().stream().map(AdminStage0Dto.BoardCommentView::getCommentId).toList();
        assertThat(ids).containsExactlyInAnyOrder("cTop", "cReply");
    }

    @Test void targetContext_deletedComment_returnedWithFlag() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "cD", "a2")));
        var cD = cmt("cD", null, "a2", "삭제된댓글", java.time.LocalDateTime.now());
        when(boardCommentRepository.findById("cD")).thenReturn(Optional.of(cD));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a3", "ACTIVE", null)));
        when(boardCommentRepository.findByPostIdOrderByCreatedAtAsc("p1")).thenReturn(List.of(cD));
        var v = service.getTargetContext("r1", "admin1").getThread().getComments().get(0);
        assertThat(v.isDeleted()).isTrue();
        assertThat(v.isTarget()).isTrue();
    }

    @Test void targetContext_commentMissing_unavailable() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "gone", "a2")));
        when(boardCommentRepository.findById("gone")).thenReturn(Optional.empty());
        assertThat(service.getTargetContext("r1", "admin1").isAvailable()).isFalse();
    }

    @Test void targetContext_nonAdmin_rejected_403() {
        when(adminAuthorizationService.isEnforced()).thenReturn(true);
        when(adminAuthorizationService.isAdmin("intruder")).thenReturn(false);
        assertThatThrownBy(() -> service.getTargetContext("r1", "intruder"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    @Test void targetContext_nonBoardType_400() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("TRADE", "t1", "s1")));
        assertThatThrownBy(() -> service.getTargetContext("r1", "admin1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    // ── 신고 당시 snapshot: 보존·수정감지·이전신고(없음) ──
    private Report reportWithSnap(ReportedSnapshot snap) {
        return Report.builder().reportId("r1").reporterId("reporter").targetType("BOARD_POST").targetId("p1")
                .status("PENDING").createdAt(java.time.LocalDateTime.now()).reportedSnapshot(snap).build();
    }

    @Test void targetContext_snapshotPreserved_unchanged() {
        var snap = new ReportedSnapshot(1, "BOARD_POST", "제목전문", "본문전문", "닉", "x", null, null, null, null, null);
        when(reportRepository.findById("r1")).thenReturn(Optional.of(reportWithSnap(snap)));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a1", "ACTIVE", null)));
        var ctx = service.getTargetContext("r1", "admin1");
        assertThat(ctx.isSnapshotAvailable()).isTrue();
        assertThat(ctx.getReportedSnapshot().title()).isEqualTo("제목전문"); // 신고 당시 보존
        assertThat(ctx.isChangedSinceReport()).isFalse(); // 현재와 동일
    }

    @Test void targetContext_postEdited_changedSinceReport() {
        var snap = new ReportedSnapshot(1, "BOARD_POST", "원래 욕설 제목", "원래 욕설 본문", "닉", "x", null, null, null, null, null);
        when(reportRepository.findById("r1")).thenReturn(Optional.of(reportWithSnap(snap)));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a1", "ACTIVE", null))); // 제목전문(상이)
        assertThat(service.getTargetContext("r1", "admin1").isChangedSinceReport()).isTrue(); // 신고 후 수정됨
    }

    @Test void targetContext_oldReport_noSnapshot_비교불가() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", "a1"))); // snapshot null
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a1", "ACTIVE", null)));
        var ctx = service.getTargetContext("r1", "admin1");
        assertThat(ctx.isSnapshotAvailable()).isFalse();
        assertThat(ctx.getReportedSnapshot()).isNull();
        assertThat(ctx.isChangedSinceReport()).isFalse(); // 비교 불가 → false
    }

    // ── null authorId 안전성(500 방지): 공식글/일반글/댓글 작성자 id null ──
    @Test void targetContext_officialPost_nullAuthor_label운영팀() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", null)));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(
                BoardPost.builder().postId("p1").type("notice").section("official").title("공지").content("내용")
                        .authorId(null).status("ACTIVE").createdAt(java.time.LocalDateTime.now()).build()));
        assertThat(service.getTargetContext("r1", "admin1").getPost().getAuthorLabel()).isEqualTo("운영팀"); // 조회 없이
    }

    @Test void targetContext_freePost_nullAuthor_labelUnknown() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_POST", "p1", null)));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", null, "ACTIVE", null)));
        assertThat(service.getTargetContext("r1", "admin1").getPost().getAuthorLabel()).isEqualTo("(알 수 없음)");
    }

    @Test void targetContext_comment_nullAuthor_labelUnknown() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "cN", null)));
        var cN = cmt("cN", null, null, "작성자 정보가 누락된 댓글", null);
        when(boardCommentRepository.findById("cN")).thenReturn(Optional.of(cN));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "a3", "ACTIVE", null)));
        when(boardCommentRepository.findByPostIdOrderByCreatedAtAsc("p1")).thenReturn(List.of(cN));
        assertThat(service.getTargetContext("r1", "admin1").getThread().getComments().get(0).getAuthorLabel())
                .isEqualTo("(알 수 없음)");
    }

    @Test void targetContext_postAuthorNull_threadStillReturned() {
        when(reportRepository.findById("r1")).thenReturn(Optional.of(report("BOARD_COMMENT", "cR", "a2")));
        var cTop = cmt("cTop", null, null, "최상위(작성자 null)", null); // thread 일부 author null
        var cR = cmt("cR", "cTop", "a2", "신고댓글", null);
        when(boardCommentRepository.findById("cR")).thenReturn(Optional.of(cR));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", null, "ACTIVE", null))); // post author null
        when(boardCommentRepository.findByPostIdOrderByCreatedAtAsc("p1")).thenReturn(List.of(cTop, cR));
        var ctx = service.getTargetContext("r1", "admin1"); // 500 안 남
        assertThat(ctx.isAvailable()).isTrue();
        var ids = ctx.getThread().getComments().stream().map(AdminStage0Dto.BoardCommentView::getCommentId).toList();
        assertThat(ids).containsExactlyInAnyOrder("cTop", "cR");
    }
}
