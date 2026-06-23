package com.fury.back.domain.report;

import com.fury.back.auth.JwtUtil;
import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.chat.ChatRoomRepository;
import com.fury.back.domain.trade.TradePostRepository;
import jakarta.servlet.http.HttpServletRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/** 게시판 신고 타입 확장 — BOARD_POST/BOARD_COMMENT 생성·작성자 해석·미존재 거부·dedup + 기존 USER 회귀. */
@ExtendWith(MockitoExtension.class)
class ReportControllerTest {

    @Mock ReportRepository reportRepository;
    @Mock JwtUtil jwtUtil;
    @Mock BlockRepository blockRepository;
    @Mock ChatRoomRepository chatRoomRepository;
    @Mock TradePostRepository tradePostRepository;
    @Mock BoardPostRepository boardPostRepository;
    @Mock BoardCommentRepository boardCommentRepository;
    @Mock ReportSnapshotService reportSnapshotService;
    @InjectMocks ReportController controller;

    private ReportedSnapshot snap() {
        return new ReportedSnapshot(1, "BOARD_POST", "제목", "본문", "닉", "2026-06-24T10:00", null, null, null, null, null);
    }

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

    private BoardPost post(String id, String author, LocalDateTime deleted) {
        return BoardPost.builder().postId(id).authorId(author).deletedAt(deleted).build();
    }

    @Test
    void boardPost_create_resolvesAuthor_and_autoBlocks() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1", null)));
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "author1")).thenReturn(false);
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "author1")).thenReturn(Optional.empty());
        when(reportSnapshotService.build("BOARD_POST", "p1")).thenReturn(snap()); // 신고 당시 원문 저장
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));

        ArgumentCaptor<Report> cap = ArgumentCaptor.forClass(Report.class);
        verify(reportRepository).save(cap.capture());
        assertThat(cap.getValue().getTargetType()).isEqualTo("BOARD_POST");
        assertThat(cap.getValue().getTargetUserId()).isEqualTo("author1"); // 작성자 해석
        assertThat(cap.getValue().getReportedSnapshot()).isNotNull(); // ★신고 당시 snapshot 보존
        verify(blockRepository).save(any(Block.class)); // 자동 차단(기존 흐름 재사용)
    }

    @Test
    void boardPost_snapshotBuildNull_rejected_noSave() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1", null)));
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "author1")).thenReturn(false);
        when(reportSnapshotService.build("BOARD_POST", "p1")).thenReturn(null); // 대상 사라짐(증거 불가)
        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));
        verify(reportRepository, never()).save(any()); // 증거 없는 신고 저장 안 함
    }

    @Test
    void boardComment_create_resolvesAuthor() {
        BoardComment c = BoardComment.builder().commentId("c1").authorId("author2").content("body").build();
        when(boardCommentRepository.findById("c1")).thenReturn(Optional.of(c));
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "author2")).thenReturn(false);
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "author2")).thenReturn(Optional.empty());
        when(reportSnapshotService.build("BOARD_COMMENT", "c1")).thenReturn(snap());
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        controller.create(req("reporter"), body("BOARD_COMMENT", "c1", "SPAM"));

        ArgumentCaptor<Report> cap = ArgumentCaptor.forClass(Report.class);
        verify(reportRepository).save(cap.capture());
        assertThat(cap.getValue().getTargetUserId()).isEqualTo("author2");
    }

    @Test
    void boardPost_missing_rejected_noSave() {
        when(boardPostRepository.findById("gone")).thenReturn(Optional.empty());
        controller.create(req("reporter"), body("BOARD_POST", "gone", "INSULT"));
        verify(reportRepository, never()).save(any());
    }

    @Test
    void boardPost_deleted_rejected_noSave() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1", LocalDateTime.now())));
        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));
        verify(reportRepository, never()).save(any());
    }

    @Test
    void boardComment_missing_rejected_noSave() {
        when(boardCommentRepository.findById("gone")).thenReturn(Optional.empty());
        controller.create(req("reporter"), body("BOARD_COMMENT", "gone", "SPAM"));
        verify(reportRepository, never()).save(any());
    }

    @Test
    void boardPost_duplicate_author_rejected() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("p1", "author1", null)));
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "author1")).thenReturn(true);
        controller.create(req("reporter"), body("BOARD_POST", "p1", "INSULT"));
        verify(reportRepository, never()).save(any()); // 1회 제한 재사용
    }

    @Test
    void invalidType_rejected() {
        controller.create(req("reporter"), body("WHATEVER", "x", "INSULT"));
        verify(reportRepository, never()).save(any());
    }

    @Test
    void user_create_regression() {
        when(reportRepository.existsByReporterIdAndTargetUserId("reporter", "victim")).thenReturn(false);
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim")).thenReturn(Optional.empty());
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        controller.create(req("reporter"), body("USER", "victim", "INSULT"));

        ArgumentCaptor<Report> cap = ArgumentCaptor.forClass(Report.class);
        verify(reportRepository).save(cap.capture());
        assertThat(cap.getValue().getTargetType()).isEqualTo("USER");
        assertThat(cap.getValue().getTargetUserId()).isEqualTo("victim");
    }
}
