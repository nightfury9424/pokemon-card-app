package com.fury.back.domain.report;

import com.fury.back.domain.block.BlockRepository;
import jakarta.persistence.EntityManager;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/**
 * 신고 영속성 통합 — ★JSONB(reported_snapshot) 실제 저장·재조회(중첩 댓글·한글·null 필드) + 생성 원자성 롤백.
 * citest = 실 PostgreSQL + ddl-auto=create-drop(엔티티에서 jsonb 컬럼 생성). 부팅 검증만 하던 BoardContextBootTest
 * 가 증명 못 하던 직렬화↔역직렬화 라운드트립을 닫는다.
 */
@SpringBootTest
@ActiveProfiles("citest")
class ReportPersistenceTest {

    @Autowired ReportRepository reportRepository;
    @Autowired EntityManager em;
    @Autowired ReportService reportService;
    @MockitoBean BlockRepository blockRepository; // 원자성 테스트에서 block 저장 실패 주입용

    @Test
    @Transactional
    void jsonb_roundtrip_nestedComments_preservesAll() {
        var snap = new ReportedSnapshot(1, "BOARD_COMMENT", null, null, null, null, null,
                "원문 게시글 제목", "cR", "cTop",
                List.of(new ReportedSnapshot.SnapshotComment("cTop", null, "최상위", "최상위 댓글 한글 본문", "2026-06-24T10:00"),
                        new ReportedSnapshot.SnapshotComment("cR", "cTop", "신고된이", "신고된 욕설 대댓글", null)));
        reportRepository.save(Report.builder().reportId("rt1").reporterId("u1").targetType("BOARD_COMMENT")
                .targetId("cR").reason("INSULT").status("PENDING").reportedSnapshot(snap).build());
        em.flush();
        em.clear(); // ★영속성 컨텍스트 비움 → DB 에서 jsonb 재조회·record 역직렬화 강제

        var s = reportRepository.findById("rt1").orElseThrow().getReportedSnapshot();
        assertThat(s).isNotNull();
        assertThat(s.version()).isEqualTo(1);
        assertThat(s.targetType()).isEqualTo("BOARD_COMMENT");
        assertThat(s.postTitle()).isEqualTo("원문 게시글 제목");
        assertThat(s.targetCommentId()).isEqualTo("cR");
        assertThat(s.comments()).hasSize(2);
        assertThat(s.comments().get(0).content()).isEqualTo("최상위 댓글 한글 본문"); // 한글 보존
        assertThat(s.comments().get(1).createdAt()).isNull();                  // null 필드 보존
        assertThat(s.title()).isNull();                                        // BOARD_POST 전용 필드 null
    }

    @Test
    @Transactional
    void jsonb_roundtrip_nullSnapshot_compatible() {
        reportRepository.save(Report.builder().reportId("rt2").reporterId("u1").targetType("TRADE")
                .targetId("t1").reason("FRAUD").status("PENDING").reportedSnapshot(null).build());
        em.flush();
        em.clear();
        assertThat(reportRepository.findById("rt2").orElseThrow().getReportedSnapshot()).isNull(); // 기존 신고 호환
    }

    @Test
    void atomicity_blockFailure_rollsBackReport() {
        // ★block 저장 실패 시 신고도 롤백(부분성공='차단만 되고 신고 없음' 방지) — 같은 @Transactional.
        when(blockRepository.findByBlockerIdAndBlockedId(any(), any())).thenReturn(Optional.empty());
        when(blockRepository.save(any())).thenThrow(new RuntimeException("block fail"));
        long before = reportRepository.count();
        assertThatThrownBy(() -> reportService.create("u1", "USER", "victim", "INSULT", null, "victim"))
                .isInstanceOf(RuntimeException.class);
        assertThat(reportRepository.count()).isEqualTo(before); // 신고 미저장(롤백)
    }
}
