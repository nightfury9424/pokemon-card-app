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

    /**
     * ★★테스트 호환 전용 오버로드(기본 autoBlock=true). 운영 런타임 경로는 ReportController 가 7-arg(autoBlock
     * 명시)만 호출한다 — 공식글/운영팀 자동차단 우회 방지를 위해 신규 운영 코드는 이 6-arg 를 호출하지 말 것.
     * (main 전수 검색 2026-06-26: 6-arg 운영 호출 0건 확인.)
     */
    @Transactional
    public String create(String reporterId, String targetType, String targetId,
                         String reason, String detail, String targetUserId) {
        return create(reporterId, targetType, targetId, reason, detail, targetUserId, true);
    }

    /**
     * @param autoBlock 신고와 동시에 작성자 자동 차단 여부. ★공식글/운영팀 댓글 등 운영팀 대상은 false
     *                  (컨트롤러가 판정) → 신고 row 만 생성하고 차단 row 는 절대 만들지 않음.
     */
    @Transactional
    public String create(String reporterId, String targetType, String targetId,
                         String reason, String detail, String targetUserId, boolean autoBlock) {
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
        // ★즉시 flush — 여기서 터지는 DB 오류는 신고 저장 단계. (RC) reports unique 적용 시 그 제약 경쟁만 중복으로,
        //   그 외(JSONB/NOT NULL/스키마)는 5xx 로 전파.
        try {
            reportRepository.saveAndFlush(report);
        } catch (DataIntegrityViolationException e) {
            throw dedupOrRethrow(e);
        }

        // 자동 차단 — ★autoBlock 일 때만(운영팀/공식 대상 제외). 같은 트랜잭션, 실패 시 신고도 롤백. 이미 차단됐으면 생략.
        if (autoBlock && targetUserId != null && !targetUserId.equals(reporterId)
                && blockRepository.findByBlockerIdAndBlockedId(reporterId, targetUserId).isEmpty()) {
            try {
                blockRepository.saveAndFlush(Block.builder()
                        .blockId(IdGenerator.generate())
                        .blockerId(reporterId)
                        .blockedId(targetUserId)
                        .build());
            } catch (DataIntegrityViolationException e) {
                // ★block unique(uq_blocks_blocker_blocked) 경쟁만 중복으로 변환. block 의 다른 제약(NOT NULL·길이 등)은 5xx.
                throw dedupOrRethrow(e);
            }
        }
        return report.getReportId();
    }

    // 알려진 dedup 제약(자동차단 unique·향후 reports 신고 unique) 위반만 "중복 신고"(400) 로, 그 외 DB 오류는 그대로(5xx).
    private static final java.util.Set<String> DEDUP_CONSTRAINTS = java.util.Set.of(
            "uq_blocks_blocker_blocked",    // 자동차단 unique(blocker_id, blocked_id) 경쟁
            "uq_reports_reporter_target");  // (RC 적용 시) 같은 신고자·대상 중복 신고

    private static RuntimeException dedupOrRethrow(DataIntegrityViolationException e) {
        if (isDedupConstraintViolation(e)) {
            return new ResponseStatusException(HttpStatus.BAD_REQUEST, "이미 신고하신 항목입니다. 검토 중이에요.");
        }
        return e; // 진짜 DB 장애를 중복으로 위장하지 않음
    }

    private static boolean isDedupConstraintViolation(DataIntegrityViolationException e) {
        StringBuilder text = new StringBuilder();
        for (Throwable t = e; t != null; t = t.getCause()) {
            if (t instanceof org.hibernate.exception.ConstraintViolationException cve && cve.getConstraintName() != null) {
                return DEDUP_CONSTRAINTS.contains(cve.getConstraintName().toLowerCase()); // Hibernate 가 제약명 추출 → 정확 매칭
            }
            if (t.getMessage() != null) text.append(' ').append(t.getMessage());
        }
        String lower = text.toString().toLowerCase(); // 추출 실패 시 방어 — 메시지 체인에서 알려진 dedup 제약명 탐지
        return DEDUP_CONSTRAINTS.stream().anyMatch(lower::contains);
    }
}
