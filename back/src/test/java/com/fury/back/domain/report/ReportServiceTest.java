package com.fury.back.domain.report;

import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.web.server.ResponseStatusException;

import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

/** 신고 생성 원자 처리 — snapshot + 신고 저장 + 자동 차단(한 트랜잭션). block unique 경쟁만 중복으로 변환, 그 외 전파. */
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
        when(reportRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));

        service.create("reporter", "BOARD_POST", "p1", "INSULT", null, "author1");

        ArgumentCaptor<Report> cap = ArgumentCaptor.forClass(Report.class);
        verify(reportRepository).saveAndFlush(cap.capture());
        assertThat(cap.getValue().getReportedSnapshot()).isNotNull();
        assertThat(cap.getValue().getTargetUserId()).isEqualTo("author1");
        verify(blockRepository).saveAndFlush(any(Block.class));
    }

    @Test void boardSnapshotNull_rejects_noSave_noBlock() {
        when(reportSnapshotService.build("BOARD_POST", "gone")).thenReturn(null);
        assertThatThrownBy(() -> service.create("reporter", "BOARD_POST", "gone", "INSULT", null, "author1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
        verify(reportRepository, never()).saveAndFlush(any());
        verify(blockRepository, never()).saveAndFlush(any());
    }

    @Test void user_noSnapshot_saves_andBlocks() {
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim")).thenReturn(Optional.empty());
        when(reportRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));
        service.create("reporter", "USER", "victim", "INSULT", null, "victim");
        verify(reportSnapshotService, never()).build(any(), any());
        verify(reportRepository).saveAndFlush(any());
        verify(blockRepository).saveAndFlush(any());
    }

    @Test void nullTargetUserId_noBlock() {
        when(reportRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));
        service.create("reporter", "BUY_ORDER", "bo1", "OTHER", null, null);
        verify(reportRepository).saveAndFlush(any());
        verify(blockRepository, never()).saveAndFlush(any());
    }

    @Test void alreadyBlocked_noDuplicateBlock() {
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim"))
                .thenReturn(Optional.of(mock(Block.class)));
        when(reportRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));
        service.create("reporter", "USER", "victim", "INSULT", null, "victim");
        verify(blockRepository, never()).saveAndFlush(any());
    }

    @Test void blockUniqueConstraint_convertedToBadRequest() {
        // ★uq_blocks_blocker_blocked 위반(동시 신고 경쟁)만 400 중복 안내로 변환.
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim")).thenReturn(Optional.empty());
        when(reportRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));
        when(blockRepository.saveAndFlush(any())).thenThrow(new DataIntegrityViolationException(
                "could not execute statement; violates unique constraint \"uq_blocks_blocker_blocked\""));
        assertThatThrownBy(() -> service.create("reporter", "USER", "victim", "INSULT", null, "victim"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void blockOtherConstraint_propagatesRaw_notMaskedAsDuplicate() {
        // ★block 의 다른 제약(NOT NULL 등)은 중복으로 위장하지 않고 그대로 전파(5xx).
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim")).thenReturn(Optional.empty());
        when(reportRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));
        when(blockRepository.saveAndFlush(any())).thenThrow(new DataIntegrityViolationException(
                "null value in column \"blocked_id\" violates not-null constraint"));
        assertThatThrownBy(() -> service.create("reporter", "USER", "victim", "INSULT", null, "victim"))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test void blockGenericFailure_propagatesRaw() {
        // DataIntegrity 아닌 block 실패(transient 등)도 그대로 전파 → @Transactional 롤백.
        when(blockRepository.findByBlockerIdAndBlockedId("reporter", "victim")).thenReturn(Optional.empty());
        when(reportRepository.saveAndFlush(any())).thenAnswer(i -> i.getArgument(0));
        when(blockRepository.saveAndFlush(any())).thenThrow(new RuntimeException("transient"));
        assertThatThrownBy(() -> service.create("reporter", "USER", "victim", "INSULT", null, "victim"))
                .isInstanceOf(RuntimeException.class).isNotInstanceOf(ResponseStatusException.class);
    }

    @Test void reportSaveDataIntegrity_propagatesRaw_blockNotReached() {
        // ★신고 저장 단계 DB 오류(JSONB/NOT NULL 등)는 중복으로 위장하지 않고 전파, block 단계 도달 안 함.
        when(reportRepository.saveAndFlush(any())).thenThrow(new DataIntegrityViolationException(
                "could not serialize jsonb column"));
        assertThatThrownBy(() -> service.create("reporter", "USER", "victim", "INSULT", null, "victim"))
                .isInstanceOf(DataIntegrityViolationException.class);
        verify(blockRepository, never()).saveAndFlush(any());
    }
}
