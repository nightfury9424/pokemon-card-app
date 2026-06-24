package com.fury.back.domain.report;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * 신고 생성 — ★snapshot 생성 + 신고 저장 + 자동 차단을 하나의 트랜잭션으로 원자 처리.
 * 어느 하나라도 실패(JSONB 직렬화·block 저장 등)하면 전체 롤백 → '차단만 되고 신고 없음' 같은 부분성공 방지.
 * (대상 작성자 해석·중복 신고 검증은 컨트롤러의 읽기 단계에서 수행하고 그 결과 targetUserId 를 받는다.)
 */
@Service
@RequiredArgsConstructor
public class ReportService {

    private final ReportRepository reportRepository;
    private final BlockRepository blockRepository;
    private final ReportSnapshotService reportSnapshotService;

    @Transactional
    public String create(String reporterId, String targetType, String targetId,
                         String reason, String detail, String targetUserId) {
        // 게시판 신고 = 신고 당시 원문 immutable snapshot + 존재·미삭제 검증(작성자 해석과 분리). null=미존재/삭제 → 거부.
        ReportedSnapshot snapshot = null;
        if ("BOARD_POST".equals(targetType) || "BOARD_COMMENT".equals(targetType)) {
            snapshot = reportSnapshotService.build(targetType, targetId);
            if (snapshot == null) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "신고할 수 없는 게시글이거나 이미 삭제되었어요.");
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
                .reportedSnapshot(snapshot)
                .build();
        // ★즉시 flush — JSONB 직렬화/NOT NULL 등 신고 저장 단계의 DB 오류는 여기서 터져 그대로 전파(5xx, 중복으로 위장 금지).
        reportRepository.saveAndFlush(report);

        // 자동 차단 — ★같은 트랜잭션. 실패 시 신고도 롤백(부분성공 방지). 이미 차단돼 있으면 생략.
        if (targetUserId != null && !targetUserId.equals(reporterId)
                && blockRepository.findByBlockerIdAndBlockedId(reporterId, targetUserId).isEmpty()) {
            try {
                blockRepository.saveAndFlush(Block.builder()
                        .blockId(IdGenerator.generate())
                        .blockerId(reporterId)
                        .blockedId(targetUserId)
                        .build());
            } catch (DataIntegrityViolationException e) {
                // ★여기 도달하는 DataIntegrityViolation 은 block unique(blocker,blocked) 경쟁뿐(신고 저장은 위에서 이미 flush됨)
                //   = 동일 신고자·대상 동시 신고(dedup 중복). tx 롤백 + 중복 안내로만 변환(다른 DB 오류는 위에서 전파).
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "이미 신고하신 항목입니다. 검토 중이에요.");
            }
        }
        return report.getReportId();
    }
}
