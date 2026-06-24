package com.fury.back.domain.report;

import org.junit.jupiter.api.Test;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/** snapshot 필수 필드 구조 검증 — INVALID(필수누락)를 레거시 null 과 합치지 않기 위한 기준. */
class ReportedSnapshotTest {

    @Test void boardPost_requiresTitleAndContent() {
        assertThat(new ReportedSnapshot(1, "BOARD_POST", "t", "c", null, null, null, null, null, null, null)
                .hasRequiredFields()).isTrue();
        assertThat(new ReportedSnapshot(1, "BOARD_POST", null, "c", null, null, null, null, null, null, null)
                .hasRequiredFields()).isFalse(); // title 누락
        assertThat(new ReportedSnapshot(1, "BOARD_POST", "t", null, null, null, null, null, null, null, null)
                .hasRequiredFields()).isFalse(); // content 누락
    }

    private ReportedSnapshot.SnapshotComment sc(String id, String content) {
        return new ReportedSnapshot.SnapshotComment(id, null, "라벨", content, null);
    }
    private ReportedSnapshot cmt(List<ReportedSnapshot.SnapshotComment> comments, String target, String top) {
        return new ReportedSnapshot(1, "BOARD_COMMENT", null, null, null, null, null, "pt", target, top, comments);
    }

    @Test void boardComment_deepValidation() {
        assertThat(cmt(List.of(sc("cTop", "최상위"), sc("cR", "대댓글")), "cR", "cTop").hasRequiredFields()).isTrue();
        // 누락/구조 이상 — 전부 false
        assertThat(cmt(null, "cR", "cTop").hasRequiredFields()).isFalse();                                  // comments null
        assertThat(cmt(List.of(), "cR", "cTop").hasRequiredFields()).isFalse();                             // 빈 배열
        assertThat(cmt(List.of(sc("cTop", "최상위")), "cR", "cTop").hasRequiredFields()).isFalse();          // 대상 댓글 없음
        assertThat(cmt(List.of(sc("cR", "대댓글")), "cR", "cTop").hasRequiredFields()).isFalse();            // 최상위 없음
        assertThat(cmt(List.of(sc("cTop", "a"), sc("cTop", "b")), "cTop", "cTop").hasRequiredFields()).isFalse(); // commentId 중복
        assertThat(cmt(List.of(sc("cTop", "최상위"), sc("cR", null)), "cR", "cTop").hasRequiredFields()).isFalse();  // content null
        assertThat(cmt(List.of(sc("cTop", "최상위"), sc(null, "x")), "cR", "cTop").hasRequiredFields()).isFalse();   // commentId null
        assertThat(cmt(List.of(sc("cTop", "최상위"), sc("cR", "대댓글")), null, "cTop").hasRequiredFields()).isFalse(); // targetCommentId 누락
        assertThat(cmt(List.of(sc("cTop", "최상위"), sc("cR", "대댓글")), "cR", null).hasRequiredFields()).isFalse();   // topCommentId 누락
    }

    @Test void unknownType_false() {
        assertThat(new ReportedSnapshot(1, "TRADE", null, null, null, null, null, null, null, null, null)
                .hasRequiredFields()).isFalse();
    }
}
