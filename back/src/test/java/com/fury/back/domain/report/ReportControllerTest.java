package com.fury.back.domain.report;

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
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "author1")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any())).thenReturn("rid");

        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));

        verify(reportService).create("reporter", "BOARD_POST", "p1", "INSULT", null, "author1"); // 작성자 해석 후 위임
    }

    @Test
    void boardComment_create_resolvesAuthor_delegates() {
        BoardComment c = BoardComment.builder().commentId("c1").authorId("author2").content("b").build();
        when(boardCommentRepository.findById("c1")).thenReturn(Optional.of(c));
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "author2")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any())).thenReturn("rid");

        controller.create(req("reporter"), body("BOARD_COMMENT", "c1", "SPAM"));

        verify(reportService).create("reporter", "BOARD_COMMENT", "c1", "SPAM", null, "author2");
    }

    @Test
    void user_create_regression_delegates() {
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "victim")).thenReturn(false);
        when(reportService.create(any(), any(), any(), any(), any(), any())).thenReturn("rid");

        controller.create(req("reporter"), body("USER", "victim", "INSULT"));

        verify(reportService).create("reporter", "USER", "victim", "INSULT", null, "victim");
    }

    @Test
    void invalidType_rejected_noDelegate() {
        controller.create(req("reporter"), body("WHATEVER", "x", "INSULT"));
        verify(reportService, never()).create(any(), any(), any(), any(), any(), any());
    }

    @Test
    void duplicate_author_rejected_noDelegate() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1")));
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "author1")).thenReturn(true);
        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));
        verify(reportService, never()).create(any(), any(), any(), any(), any(), any()); // 중복 → 위임 안 함
    }

    @Test
    void serviceRejects_handledNotThrown() {
        // board 대상 미존재/삭제 → service 가 BAD_REQUEST → 컨트롤러가 catch 해서 fail 응답(예외 전파 X).
        when(boardPostRepository.findById("gone")).thenReturn(Optional.empty());
        when(reportService.create(any(), any(), any(), any(), any(), any()))
                .thenThrow(new ResponseStatusException(HttpStatus.BAD_REQUEST, "신고할 수 없는 게시글이거나 이미 삭제되었어요."));
        controller.create(req("reporter"), body("BOARD_POST", "gone", "INSULT")); // throw 하지 않음
        verify(reportService).create(any(), any(), any(), any(), any(), any());
    }
}
