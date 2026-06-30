package com.fury.back.domain.report;

import com.fury.back.BackApplication;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.context.ActiveProfiles;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * #14 신고 중복 partial unique index — 실제 PostgreSQL(citest) 강제력 검증.
 * reports 테이블은 create-drop 으로 생성되나 partial unique INDEX 는 엔티티 미매핑 → @BeforeEach 에서 마이그 인덱스 적용.
 * ★@Transactional 미사용(각 saveAndFlush 자체 tx 커밋) — unique 위반이 다음 작업을 오염시키지 않게.
 */
@SpringBootTest(classes = BackApplication.class)
@ActiveProfiles("citest")
class ReportDedupIntegrationTest {

    @Autowired ReportRepository reportRepository;
    @Autowired JdbcTemplate jdbc;

    private static final LocalDateTime T = LocalDateTime.of(2026, 6, 26, 0, 0);

    private Report report(String id, String reporter, String type, String targetId, String targetUser) {
        return Report.builder().reportId(id).reporterId(reporter).targetType(type)
                .targetId(targetId).targetUserId(targetUser).reason("INSULT").status("PENDING").createdAt(T).build();
    }

    @BeforeEach
    void applyMigrationIndexes() {
        jdbc.execute("DELETE FROM reports");
        jdbc.execute("DROP INDEX IF EXISTS uq_reports_reporter_target");
        jdbc.execute("DROP INDEX IF EXISTS uq_reports_reporter_board_target");
        // 마이그 최종 상태: 비게시판 per-user + 게시판 per-target
        jdbc.execute("CREATE UNIQUE INDEX uq_reports_reporter_target ON reports (reporter_id, target_user_id) "
                + "WHERE target_user_id IS NOT NULL AND target_type NOT IN ('BOARD_POST','BOARD_COMMENT')");
        jdbc.execute("CREATE UNIQUE INDEX uq_reports_reporter_board_target ON reports (reporter_id, target_type, target_id) "
                + "WHERE target_type IN ('BOARD_POST','BOARD_COMMENT')");
    }

    @Test void board_sameTarget_secondViolates_rowMax1() {
        reportRepository.saveAndFlush(report("r1", "rep", "BOARD_POST", "p1", "authorX"));
        assertThatThrownBy(() -> reportRepository.saveAndFlush(report("r2", "rep", "BOARD_POST", "p1", "authorX")))
                .isInstanceOf(DataIntegrityViolationException.class);
        assertThat(reportRepository.count()).isEqualTo(1); // 경쟁/재신고 시 row 최대 1
    }

    @Test void board_differentPost_sameAuthor_bothOk() {
        reportRepository.saveAndFlush(report("r1", "rep", "BOARD_POST", "p1", "authorX"));
        reportRepository.saveAndFlush(report("r2", "rep", "BOARD_POST", "p2", "authorX")); // per-target → 같은 작성자 다른 글 허용
        assertThat(reportRepository.count()).isEqualTo(2);
    }

    @Test void boardComment_sameTarget_secondViolates() {
        reportRepository.saveAndFlush(report("r1", "rep", "BOARD_COMMENT", "c1", "authorX"));
        assertThatThrownBy(() -> reportRepository.saveAndFlush(report("r2", "rep", "BOARD_COMMENT", "c1", "authorX")))
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test void user_sameTargetUser_secondViolates() {
        reportRepository.saveAndFlush(report("r1", "rep", "USER", "victim", "victim"));
        assertThatThrownBy(() -> reportRepository.saveAndFlush(report("r2", "rep", "USER", "victim", "victim")))
                .isInstanceOf(DataIntegrityViolationException.class); // per-user 보존
    }

    @Test void boardAndUser_sameUser_independent_bothOk() {
        reportRepository.saveAndFlush(report("r1", "rep", "USER", "X", "X"));        // per-user index
        reportRepository.saveAndFlush(report("r2", "rep", "BOARD_POST", "p1", "X")); // board 는 per-user index 에서 제외 → 독립
        assertThat(reportRepository.count()).isEqualTo(2);
    }

    @Test void rollback_restoresOriginalPerUser_blocksBoardSameAuthor() {
        // 롤백 SQL 상태: board per-target 제거 + 원본 per-user(board 포함) 복원
        jdbc.execute("DROP INDEX IF EXISTS uq_reports_reporter_board_target");
        jdbc.execute("DROP INDEX uq_reports_reporter_target");
        jdbc.execute("CREATE UNIQUE INDEX uq_reports_reporter_target ON reports (reporter_id, target_user_id) WHERE target_user_id IS NOT NULL");
        reportRepository.saveAndFlush(report("r1", "rep", "BOARD_POST", "p1", "authorX"));
        // 원본 index 는 board 도 per-user 로 → 같은 작성자 다른 글이 막힘(롤백 정확성 확인)
        assertThatThrownBy(() -> reportRepository.saveAndFlush(report("r2", "rep", "BOARD_POST", "p2", "authorX")))
                .isInstanceOf(DataIntegrityViolationException.class);
    }
}
