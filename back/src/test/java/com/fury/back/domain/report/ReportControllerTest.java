package com.fury.back.domain.report;

import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.auth.JwtUtil;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.chat.ChatRoomRepository;
import com.fury.back.domain.trade.TradePostRepository;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.web.server.ResponseStatusException;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

/** 신고 컨트롤러 — 타입검증·작성자 해석·중복방지·서비스 위임. (저장·차단·snapshot 원자처리는 ReportServiceTest.) */
@ExtendWith(MockitoExtension.class)
class ReportControllerTest {

    @Mock ReportRepository reportRepository;
    @Mock JwtUtil jwtUtil;
    @Mock ChatRoomRepository chatRoomRepository;
    @Mock TradePostRepository tradePostRepository;
    @Mock BoardPostRepository boardPostRepository;
    @Mock BoardCommentRepository boardCommentRepository;
    @Mock ReportService reportService;
    @Mock AdminAuthorizationService adminAuthorizationService;
    @InjectMocks ReportController controller;

    private HttpServletRequest req(String userId) {
        HttpServletRequest r = mock(HttpServletRequest.class);
        when(r.getHeader("Authorization")).thenReturn("Bearer tok");
        when(jwtUtil.isValid("tok")).thenReturn(true);
        when(jwtUtil.extractUserId("tok")).thenReturn(userId);
        return r;
    }

    private Map<String, Object> body(String type, String id, String reason) {
        Map<String, Object> m = new HashMap<>();
        m.put("targetType", type);
        m.put("targetId", id);
        m.put("reason", reason);
        return m;
    }

    private BoardPost post(String id, String author) {
        return BoardPost.builder().postId(id).authorId(author).build();
    }

    @Test
    void boardPost_create_resolvesAuthor_delegates() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1")));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_POST", "p1")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn("rid");

        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));

        verify(reportService).create("reporter", "BOARD_POST", "p1", "INSULT", null, "author1", true); // 작성자 해석 후 위임(일반글=autoBlock true)
    }

    @Test
    void boardPost_adminAuthor_freeType_autoBlockFalse() {
        // ★운영팀이 쓴 자유글 신고 → 타입은 free(비공식)지만 작성자가 운영팀 → autoBlock=false (nightfury 재차단 방지).
        when(boardPostRepository.findById("pf")).thenReturn(Optional.of(post("pf", "adminAuthor")));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_POST", "pf")).thenReturn(false);
        when(adminAuthorizationService.isAdmin("adminAuthor")).thenReturn(true);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn("rid");

        controller.create(req("reporter"), body("BOARD_POST", "pf", "INSULT"));

        verify(reportService).create("reporter", "BOARD_POST", "pf", "INSULT", null, "adminAuthor", false);
    }

    @Test
    void boardComment_create_resolvesAuthor_delegates() {
        BoardComment c = BoardComment.builder().commentId("c1").authorId("author2").content("b").build();
        when(boardCommentRepository.findById("c1")).thenReturn(Optional.of(c));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_COMMENT", "c1")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn("rid");

        controller.create(req("reporter"), body("BOARD_COMMENT", "c1", "SPAM"));

        verify(reportService).create("reporter", "BOARD_COMMENT", "c1", "SPAM", null, "author2", true); // 일반 사용자 댓글=autoBlock true
    }

    @Test
    void user_create_regression_delegates() {
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "victim")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn("rid");

        controller.create(req("reporter"), body("USER", "victim", "INSULT"));

        verify(reportService).create("reporter", "USER", "victim", "INSULT", null, "victim", true); // USER=기존 자동차단 유지
    }

    @Test
    void boardPost_differentTarget_sameAuthor_delegates() {
        // ★#10: 같은 작성자의 ★다른 게시글은 각각 신고 가능(per-target). p2 미신고 → 위임됨.
        when(boardPostRepository.findById("p2")).thenReturn(Optional.of(post("p2", "author1")));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_POST", "p2")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn("rid");
        controller.create(req("reporter"), body("BOARD_POST", "p2", "INSULT"));
        verify(reportService).create("reporter", "BOARD_POST", "p2", "INSULT", null, "author1", true);
    }

    @Test
    void user_duplicate_sameTarget_rejected_noDelegate() {
        // ★USER 중복 정책 보존: 같은 사용자 재신고는 기존대로 per-user 로 차단.
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "victim")).thenReturn(true);
        controller.create(req("reporter"), body("USER", "victim", "INSULT"));
        verify(reportService, never()).create(any(), any(), any(), any(), any(), any(), anyBoolean());
    }

    @Test
    void boardComment_differentTarget_sameAuthor_delegates() {
        // ★#10: 같은 작성자의 다른 댓글은 각각 신고 가능(per-target).
        when(boardCommentRepository.findById("c2")).thenReturn(
                Optional.of(BoardComment.builder().commentId("c2").authorId("author2").content("b").build()));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_COMMENT", "c2")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn("rid");
        controller.create(req("reporter"), body("BOARD_COMMENT", "c2", "SPAM"));
        verify(reportService).create("reporter", "BOARD_COMMENT", "c2", "SPAM", null, "author2", true);
    }

    @Test
    void boardComment_duplicate_sameTarget_rejected_noDelegate() {
        // ★#10: 동일 댓글 재신고는 400(per-target).
        when(boardCommentRepository.findById("c1")).thenReturn(
                Optional.of(BoardComment.builder().commentId("c1").authorId("author2").content("b").build()));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_COMMENT", "c1")).thenReturn(true);
        controller.create(req("reporter"), body("BOARD_COMMENT", "c1", "SPAM"));
        verify(reportService, never()).create(any(), any(), any(), any(), any(), any(), anyBoolean());
    }

    @Test
    void boardPost_and_comment_sameTargetId_independent() {
        // ★#10: BOARD_POST 와 BOARD_COMMENT 의 targetId 가 같아도 targetType 이 달라 독립 dedup → 둘 다 위임.
        when(boardPostRepository.findById("x1")).thenReturn(Optional.of(post("x1", "author1")));
        when(boardCommentRepository.findById("x1")).thenReturn(
                Optional.of(BoardComment.builder().commentId("x1").authorId("author2").content("b").build()));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_POST", "x1")).thenReturn(false);
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_COMMENT", "x1")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean())).thenReturn("rid");
        controller.create(req("reporter"), body("BOARD_POST", "x1", "INSULT"));
        controller.create(req("reporter"), body("BOARD_COMMENT", "x1", "SPAM"));
        verify(reportService).create("reporter", "BOARD_POST", "x1", "INSULT", null, "author1", true);
        verify(reportService).create("reporter", "BOARD_COMMENT", "x1", "SPAM", null, "author2", true);
    }

    @Test
    void invalidType_rejected_noDelegate() {
        controller.create(req("reporter"), body("WHATEVER", "x", "INSULT"));
        verify(reportService, never()).create(any(), any(), any(), any(), any(), any(), anyBoolean());
    }

    @Test
    void otherReason_blankDetail_rejected_noDelegate() {
        // ★기타(OTHER) 사유 직접입력 누락 → 서버가 거부(Front 우회 차단). 위임 안 함.
        controller.create(req("reporter"), body("BOARD_POST", "p1", "OTHER")); // detail 없음
        verify(reportService, never()).create(any(), any(), any(), any(), any(), any(), anyBoolean());
    }

    @Test
    void duplicate_author_rejected_noDelegate() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1")));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_POST", "p1")).thenReturn(true);
        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));
        verify(reportService, never()).create(any(), any(), any(), any(), any(), any(), anyBoolean()); // 중복 → 위임 안 함
    }

    @Test
    void serviceRejects_handledNotThrown() {
        // board 대상 미존재/삭제 → service 가 BAD_REQUEST → 컨트롤러가 catch 해서 fail 응답(예외 전파 X).
        when(boardPostRepository.findById("gone")).thenReturn(Optional.empty());
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean()))
                .thenThrow(new ResponseStatusException(HttpStatus.BAD_REQUEST, "신고할 수 없는 게시글이거나 이미 삭제되었어요."));
        controller.create(req("reporter"), body("BOARD_POST", "gone", "INSULT")); // throw 하지 않음
        verify(reportService).create(any(), any(), any(), any(), any(), any(), anyBoolean());
    }

    @Test
    void genericDataIntegrity_propagates_notMaskedAsDuplicate() {
        // ★block 경쟁은 service 가 400 으로 변환. 그 외 DataIntegrityViolation(JSONB/NOT NULL 등)은 컨트롤러가
        //   중복으로 위장하지 않고 그대로 전파(5xx) — 진짜 DB 장애를 숨기지 않음.
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1")));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_POST", "p1")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean()))
                .thenThrow(new org.springframework.dao.DataIntegrityViolationException("schema mismatch"));
        assertThatThrownBy(() -> controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT")))
                .isInstanceOf(org.springframework.dao.DataIntegrityViolationException.class);
    }

    @Test
    void nonBadRequestStatus_rethrown_notFlattened() {
        // 400 외 ResponseStatusException 은 badRequest 로 뭉개지 않고 전파(상태 의미 보존).
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1")));
        when(reportRepository.existsByReporterIdAndTargetTypeAndTargetId("reporter", "BOARD_POST", "p1")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any(), anyBoolean()))
                .thenThrow(new ResponseStatusException(HttpStatus.FORBIDDEN, "nope"));
        assertThatThrownBy(() -> controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT")))
                .isInstanceOf(ResponseStatusException.class);
    }
}
