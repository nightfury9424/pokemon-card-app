package com.fury.back.domain.admin;

import com.fury.back.auth.AdminAllowlistFilter;
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

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
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
}
