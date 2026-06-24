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

    @Test void boardComment_requiresIdsAndCommentsNonNull() {
        assertThat(new ReportedSnapshot(1, "BOARD_COMMENT", null, null, null, null, null, "pt", "c1", "cTop", List.of())
                .hasRequiredFields()).isTrue(); // 빈 배열은 OK(절대 null 금지)
        assertThat(new ReportedSnapshot(1, "BOARD_COMMENT", null, null, null, null, null, "pt", null, "cTop", List.of())
                .hasRequiredFields()).isFalse(); // targetCommentId 누락
        assertThat(new ReportedSnapshot(1, "BOARD_COMMENT", null, null, null, null, null, "pt", "c1", null, List.of())
                .hasRequiredFields()).isFalse(); // topCommentId 누락
        assertThat(new ReportedSnapshot(1, "BOARD_COMMENT", null, null, null, null, null, "pt", "c1", "cTop", null)
                .hasRequiredFields()).isFalse(); // comments null 금지
    }

    @Test void unknownType_false() {
        assertThat(new ReportedSnapshot(1, "TRADE", null, null, null, null, null, null, null, null, null)
                .hasRequiredFields()).isFalse();
    }
}
