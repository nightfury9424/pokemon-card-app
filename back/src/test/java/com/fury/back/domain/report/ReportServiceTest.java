package com.fury.back.domain.report;

import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/** 신고 생성 원자 처리 — snapshot + 신고 저장 + 자동 차단(같은 트랜잭션). block 실패 전파(롤백 보장). */
@ExtendWith(MockitoExtension.class)
class ReportServiceTest {

    @Mock ReportRepository reportRepository;
    @Mock BlockRepository blockRepository;
    @Mock ReportSnapshotService reportSnapshotService;
    @InjectMocks ReportService service;

    private ReportedSnapshot snap() {
        return new ReportedSnapshot(1, "BOARD_POST", "제목", "본문", "닉", "x", null, null, null, null, null);
    }

    @Test void boardPost_buildsSnapshot_saves_andBlocks() {
        when(reportSnapshotService.build("BOARD_POST", "p1")).thenReturn(snap());
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "author1")).thenReturn(Optional.empty());
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        service.create("reporter", "BOARD_POST", "p1", "INSULT", null, "author1");

        ArgumentCaptor<Report> cap = ArgumentCaptor.forClass(Report.class);
        verify(reportRepository).save(cap.capture());
        assertThat(cap.getValue().getReportedSnapshot()).isNotNull();   // 신고 당시 snapshot 저장
        assertThat(cap.getValue().getTargetUserId()).isEqualTo("author1");
        verify(blockRepository).save(any(Block.class));                 // 자동 차단
    }

    @Test void boardSnapshotNull_rejects_noSave_noBlock() {
        when(reportSnapshotService.build("BOARD_POST", "gone")).thenReturn(null); // 미존재/삭제
        assertThatThrownBy(() -> service.create("reporter", "BOARD_POST", "gone", "INSULT", null, "author1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
        verify(reportRepository, never()).save(any());
        verify(blockRepository, never()).save(any());
    }

    @Test void user_noSnapshot_saves_andBlocks() {
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim")).thenReturn(Optional.empty());
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));

        service.create("reporter", "USER", "victim", "INSULT", null, "victim");

        verify(reportSnapshotService, never()).build(any(), any()); // 비-board snapshot 없음
        verify(reportRepository).save(any());
        verify(blockRepository).save(any());
    }

    @Test void nullTargetUserId_noBlock() {
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        service.create("reporter", "BUY_ORDER", "bo1", "OTHER", null, null);
        verify(reportRepository).save(any());
        verify(blockRepository, never()).save(any()); // targetUserId null → 자동차단 없음
    }

    @Test void alreadyBlocked_noDuplicateBlock() {
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim"))
                .thenReturn(Optional.of(mock(Block.class)));
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        service.create("reporter", "USER", "victim", "INSULT", null, "victim");
        verify(blockRepository, never()).save(any()); // 이미 차단 → 중복 안 함
    }

    @Test void blockFailure_propagates_notSwallowed() {
        // ★block 저장 실패 → 예외 전파(swallow X) → @Transactional 이 신고도 롤백(부분성공 방지)
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim")).thenReturn(Optional.empty());
        when(reportRepository.save(any())).thenAnswer(i -> i.getArgument(0));
        when(blockRepository.save(any())).thenThrow(new RuntimeException("block fail"));
        assertThatThrownBy(() -> service.create("reporter", "USER", "victim", "INSULT", null, "victim"))
                .isInstanceOf(RuntimeException.class);
    }
}
