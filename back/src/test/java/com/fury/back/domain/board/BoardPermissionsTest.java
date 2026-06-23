package com.fury.back.domain.board;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 게시판 소유권·액션 플래그 매트릭스(순수 단위, 스프링/DB 무관).
 * 목록·상세 공통 헬퍼 BoardPermissions 의 결정적 검증.
 */
class BoardPermissionsTest {

    // ── 게시글 ──
    @Test void post_anonymous_all_false() {
        var f = BoardPermissions.forPost(null, "u1", "free", "ACTIVE", false);
        assertThat(f.mine()).isFalse();
        assertThat(f.canEdit()).isFalse();
        assertThat(f.canDelete()).isFalse();
        assertThat(f.canReport()).isFalse();
        assertThat(f.canBlock()).isFalse();
        // blank viewer 도 비로그인 취급
        assertThat(BoardPermissions.forPost("  ", "u1", "free", "ACTIVE", false).canReport()).isFalse();
    }

    @Test void post_owner_community_edit_delete_only() {
        var f = BoardPermissions.forPost("u1", "u1", "free", "ACTIVE", false);
        assertThat(f.mine()).isTrue();
        assertThat(f.canEdit()).isTrue();
        assertThat(f.canDelete()).isTrue();
        assertThat(f.canReport()).isFalse(); // 자기 신고 불가
        assertThat(f.canBlock()).isFalse();  // 자기 차단 불가
    }

    @Test void post_other_community_report_block_only() {
        var f = BoardPermissions.forPost("viewer", "u1", "free", "ACTIVE", false);
        assertThat(f.mine()).isFalse();
        assertThat(f.canEdit()).isFalse();
        assertThat(f.canDelete()).isFalse();
        assertThat(f.canReport()).isTrue();
        assertThat(f.canBlock()).isTrue();
    }

    @Test void post_official_owner_mine_true_but_no_app_actions() {
        // ★공식글 작성자가 본인이어도 mine=true 이되 앱 수정/삭제/신고/차단 전부 불가
        var f = BoardPermissions.forPost("admin", "admin", "notice", "ACTIVE", false);
        assertThat(f.mine()).isTrue();
        assertThat(f.canEdit()).isFalse();
        assertThat(f.canDelete()).isFalse();
        assertThat(f.canReport()).isFalse();
        assertThat(f.canBlock()).isFalse();
    }

    @Test void post_official_other_all_false() {
        var f = BoardPermissions.forPost("viewer", "admin", "event", "ACTIVE", false);
        assertThat(f.mine()).isFalse();
        assertThat(f.canReport()).isFalse(); // 공식글은 신고/차단 불가
        assertThat(f.canBlock()).isFalse();
    }

    @Test void post_owner_canEdit_requires_active() {
        // HIDDEN/삭제 글은 수정 불가(본인이어도)
        assertThat(BoardPermissions.forPost("u1", "u1", "free", "HIDDEN", false).canEdit()).isFalse();
        assertThat(BoardPermissions.forPost("u1", "u1", "free", "ACTIVE", true).canEdit()).isFalse();
    }

    // ── 댓글/대댓글 ──
    @Test void comment_anonymous_all_false() {
        var f = BoardPermissions.forComment(null, "u1", "c1", null, false, true);
        assertThat(f.mine()).isFalse();
        assertThat(f.canDelete()).isFalse();
        assertThat(f.canReply()).isFalse();
        assertThat(f.canReport()).isFalse();
        assertThat(f.canBlock()).isFalse();
    }

    @Test void comment_owner_topLevel() {
        var f = BoardPermissions.forComment("u1", "u1", "c1", null, false, true);
        assertThat(f.mine()).isTrue();
        assertThat(f.canDelete()).isTrue();
        assertThat(f.canReply()).isTrue();
        assertThat(f.replyTargetCommentId()).isEqualTo("c1"); // 최상위 = 자기 id
        assertThat(f.canReport()).isFalse();
        assertThat(f.canBlock()).isFalse();
    }

    @Test void comment_other_topLevel() {
        var f = BoardPermissions.forComment("viewer", "u1", "c1", null, false, true);
        assertThat(f.mine()).isFalse();
        assertThat(f.canDelete()).isFalse();
        assertThat(f.canReply()).isTrue();
        assertThat(f.replyTargetCommentId()).isEqualTo("c1");
        assertThat(f.canReport()).isTrue();
        assertThat(f.canBlock()).isTrue();
    }

    @Test void comment_reply_target_points_to_topLevel_parent() {
        // ★대댓글도 답글 가능, replyTarget 은 항상 최상위 부모(2단 이상 금지)
        var mineReply = BoardPermissions.forComment("u1", "u1", "r1", "top1", false, true);
        assertThat(mineReply.canReply()).isTrue();
        assertThat(mineReply.replyTargetCommentId()).isEqualTo("top1");
        assertThat(mineReply.canDelete()).isTrue();
        var otherReply = BoardPermissions.forComment("viewer", "u2", "r1", "top1", false, true);
        assertThat(otherReply.canReply()).isTrue();
        assertThat(otherReply.replyTargetCommentId()).isEqualTo("top1");
        assertThat(otherReply.canReport()).isTrue();
        assertThat(otherReply.canBlock()).isTrue();
    }

    @Test void comment_deleted_placeholder_all_false() {
        var f = BoardPermissions.forComment("viewer", "u1", "c1", null, true, true);
        assertThat(f.mine()).isFalse();
        assertThat(f.canDelete()).isFalse();
        assertThat(f.canReply()).isFalse();
        assertThat(f.replyTargetCommentId()).isNull();
        assertThat(f.canReport()).isFalse();
        assertThat(f.canBlock()).isFalse();
    }

    @Test void comment_admin_badge_NOT_exempt_from_report() {
        // ★운영자 뱃지 댓글이어도 (자유게시판·타인·미삭제) 신고/차단 가능 — isAdmin 미고려
        var f = BoardPermissions.forComment("viewer", "adminUser", "c1", null, false, true);
        assertThat(f.canReport()).isTrue();
        assertThat(f.canBlock()).isTrue();
    }

    @Test void comment_nonCommunity_no_reply_report_block() {
        // 공식글 댓글(존재하면 안 되나 방어): community=false → reply/report/block 불가
        var f = BoardPermissions.forComment("viewer", "u1", "c1", null, false, false);
        assertThat(f.canReply()).isFalse();
        assertThat(f.canReport()).isFalse();
        assertThat(f.canBlock()).isFalse();
    }
}
