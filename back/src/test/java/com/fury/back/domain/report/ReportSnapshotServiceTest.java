package com.fury.back.domain.report;

import com.fury.back.domain.board.BoardComment;
import com.fury.back.domain.board.BoardPost;
import com.fury.back.domain.board.BoardPostRepository;
import com.fury.back.domain.board.BoardCommentRepository;
import com.fury.back.domain.user.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;

/** snapshot 생성 — 정상 v1 + 불완전 snapshot 저장 거부(loud) + 미존재=null(거부 책임). */
@ExtendWith(MockitoExtension.class)
class ReportSnapshotServiceTest {

    @Mock BoardPostRepository boardPostRepository;
    @Mock com.fury.back.domain.board.BoardPostImageRepository boardPostImageRepository;
    @Mock BoardCommentRepository boardCommentRepository;
    @Mock UserRepository userRepository;
    @InjectMocks ReportSnapshotService service;

    private BoardPost post(String title, String content) {
        return BoardPost.builder().postId("p1").type("free").title(title).content(content)
                .authorId("a").status("ACTIVE").createdAt(LocalDateTime.now()).build();
    }

    @Test void post_valid_buildsV1WithRequiredFields() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("t", "c")));
        when(userRepository.findAllById(any())).thenReturn(List.of());
        var snap = service.build("BOARD_POST", "p1");
        assertThat(snap.version()).isEqualTo(ReportedSnapshot.CURRENT_VERSION);
        assertThat(snap.hasRequiredFields()).isTrue();
    }

    @Test void post_snapshot_capturesImageKeysAndCount() {
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("t", "c")));
        when(userRepository.findAllById(any())).thenReturn(List.of());
        when(boardPostImageRepository.findByPostIdOrderBySortOrderAsc("p1")).thenReturn(List.of(
                com.fury.back.domain.board.BoardPostImage.builder().imageId("i1").postId("p1")
                        .storageKey("uploads/board/k1.jpg").sortOrder(0)
                        .createdAt(java.time.LocalDateTime.now()).build(),
                com.fury.back.domain.board.BoardPostImage.builder().imageId("i2").postId("p1")
                        .storageKey("uploads/board/k2.jpg").sortOrder(1)
                        .createdAt(java.time.LocalDateTime.now()).build()));
        var snap = service.build("BOARD_POST", "p1");
        // ★신고 당시 이미지 = raw storage key 보존(이후 수정·삭제돼도). secure proxy 변환은 관리자 조회 측.
        assertThat(snap.imageCount()).isEqualTo(2);
        assertThat(snap.imageKeys()).containsExactly("uploads/board/k1.jpg", "uploads/board/k2.jpg");
    }

    @Test void post_missingContent_throws_notStored() {
        // content 는 NOT NULL 이라 정상엔 없지만, 불완전 snapshot 저장 금지(loud fail) 방어 확인.
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("t", null)));
        when(userRepository.findAllById(any())).thenReturn(List.of());
        assertThatThrownBy(() -> service.build("BOARD_POST", "p1"))
                .isInstanceOf(IllegalStateException.class);
    }

    @Test void missing_returnsNull_notInvalid() {
        when(boardPostRepository.findById("gone")).thenReturn(Optional.empty());
        assertThat(service.build("BOARD_POST", "gone")).isNull(); // 미존재 = null(생성측 거부), INVALID 아님
    }

    @Test void nonBoard_returnsNull() {
        assertThat(service.build("TRADE", "t1")).isNull();
    }

    @Test void comment_valid_buildsDeepValidSnapshot() {
        var top = BoardComment.builder().commentId("cTop").postId("p1").authorId("a1").content("최상위").createdAt(LocalDateTime.now()).build();
        var reply = BoardComment.builder().commentId("cR").parentCommentId("cTop").postId("p1").authorId("a2").content("신고된 대댓글").createdAt(LocalDateTime.now()).build();
        when(boardCommentRepository.findById("cR")).thenReturn(Optional.of(reply));
        when(boardPostRepository.findById("p1")).thenReturn(Optional.of(post("제목", "본문")));
        when(boardCommentRepository.findByPostIdOrderByCreatedAtAsc("p1")).thenReturn(List.of(top, reply));
        when(userRepository.findAllById(any())).thenReturn(List.of());
        var snap = service.build("BOARD_COMMENT", "cR"); // 대댓글 신고 → 부모 thread snapshot
        assertThat(snap.hasRequiredFields()).isTrue();
        assertThat(snap.targetCommentId()).isEqualTo("cR");
        assertThat(snap.topCommentId()).isEqualTo("cTop");
        assertThat(snap.comments()).hasSize(2);
    }
}
