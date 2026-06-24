package com.fury.back.domain.report;

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
}
