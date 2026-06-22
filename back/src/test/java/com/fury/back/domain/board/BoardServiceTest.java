package com.fury.back.domain.board;

import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.board.dto.BoardCommentDto;
import com.fury.back.domain.board.dto.BoardPostDetailDto;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BoardServiceTest {

    @Mock BoardPostRepository postRepo;
    @Mock BoardCommentRepository commentRepo;
    @Mock BlockRepository blockRepo;
    @Mock UserRepository userRepo;
    @InjectMocks BoardService service;

    private static final LocalDateTime T1 = LocalDateTime.of(2026, 6, 23, 10, 0, 0);

    private BoardPost active(String id, String type, String section, String author) {
        return BoardPost.builder().postId(id).type(type).section(section).title("t").content("b")
                .authorId(author).pinned(false).answered(false).viewCount(0).likeCount(0)
                .status("ACTIVE").createdAt(T1).build();
    }

    private BoardComment c(String id, String parent, String author, boolean deleted, boolean admin) {
        return BoardComment.builder().commentId(id).postId("p").parentCommentId(parent).authorId(author)
                .content("body").admin(admin).accepted(false).createdAt(T1)
                .deletedAt(deleted ? T1 : null).build();
    }

    // ── 검증 400 ──
    @Test void feed_invalidSection_400() {
        assertThatThrownBy(() -> service.getFeed("nope", null, null, 0, 20))
                .isInstanceOf(ResponseStatusException.class)
                .hasMessageContaining("400");
    }

    @Test void feed_invalidType_400() {
        assertThatThrownBy(() -> service.getFeed(null, "nope", null, 0, 20))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void feed_section_type_mismatch_400() {
        // qna 타입은 community 섹션에 속하지 않음
        assertThatThrownBy(() -> service.getFeed("community", "qna", null, 0, 20))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void feed_negativePage_400() {
        assertThatThrownBy(() -> service.getFeed(null, null, null, -1, 20))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    // ── size clamp ──
    @Test void feed_size_clamped_to_max_50_and_default_20() {
        when(postRepo.findFeed(any(), any(), any(), any())).thenReturn(new PageImpl<>(List.of()));
        ArgumentCaptor<Pageable> cap = ArgumentCaptor.forClass(Pageable.class);

        service.getFeed(null, null, null, 0, 999); // size>50 → 50
        service.getFeed(null, null, null, 0, 0);   // size<=0 → 20

        verify(postRepo, times(2)).findFeed(any(), any(), any(), cap.capture());
        assertThat(cap.getAllValues().get(0).getPageSize()).isEqualTo(50);
        assertThat(cap.getAllValues().get(1).getPageSize()).isEqualTo(20);
    }

    // ── detail 404 ──
    @Test void detail_missing_404() {
        when(postRepo.findById("x")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.getDetail("x", null))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void detail_deleted_404() {
        BoardPost p = BoardPost.builder().postId("p").type("free").section("community").title("t").content("b")
                .authorId("u1").pinned(false).answered(false).viewCount(0).likeCount(0)
                .status("ACTIVE").createdAt(T1).deletedAt(T1).build();
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        assertThatThrownBy(() -> service.getDetail("p", null))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void detail_hidden_404() {
        BoardPost p = BoardPost.builder().postId("p").type("free").section("community").title("t").content("b")
                .authorId("u1").pinned(false).answered(false).viewCount(0).likeCount(0)
                .status("HIDDEN").createdAt(T1).build();
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        assertThatThrownBy(() -> service.getDetail("p", null))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void detail_blockedAuthor_404_for_viewer() {
        when(postRepo.findById("p")).thenReturn(Optional.of(active("p", "free", "community", "ax")));
        when(blockRepo.existsByBlockerIdAndBlockedId("viewer", "ax")).thenReturn(true);
        assertThatThrownBy(() -> service.getDetail("p", "viewer"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    // ── detail happy + 삭제 댓글 placeholder ──
    @Test void detail_assembles_tree_with_deleted_placeholder_rules() {
        when(postRepo.findById("p")).thenReturn(Optional.of(active("p", "notice", "official", "admin")));
        // c1 삭제 + 답글(c2 활성) → placeholder ; c3 삭제 무답글 → 제외 ; c4 활성 + 답글 c5 삭제 → c4만(c5 제외)
        when(commentRepo.findByPostIdOrderByCreatedAtAsc("p")).thenReturn(List.of(
                c("c1", null, "u1", true, false),
                c("c2", "c1", "u2", false, false),
                c("c3", null, "u3", true, false),
                c("c4", null, "u4", false, false),
                c("c5", "c4", "u5", true, false)
        ));
        User u2 = mock(User.class); when(u2.getUserId()).thenReturn("u2"); when(u2.getNickname()).thenReturn("둘이");
        User u4 = mock(User.class); when(u4.getUserId()).thenReturn("u4"); when(u4.getNickname()).thenReturn("넷이");
        when(userRepo.findAllById(anySet())).thenReturn(List.of(u2, u4));

        BoardPostDetailDto d = service.getDetail("p", null);

        assertThat(d.author()).isEqualTo("운영팀"); // notice = 관리자 타입
        assertThat(d.commentCount()).isEqualTo(2); // 활성 댓글만(c2,c4). c1/c3/c5 삭제 제외
        // 트리: [c1 placeholder(+c2), c4(답글없음)] — c3(삭제·무답글) 제외
        assertThat(d.comments()).extracting(BoardCommentDto::id).containsExactly("c1", "c4");
        BoardCommentDto c1 = d.comments().get(0);
        assertThat(c1.author()).isEqualTo("(삭제됨)");
        assertThat(c1.body()).isEqualTo("삭제된 댓글입니다");
        assertThat(c1.replies()).extracting(BoardCommentDto::id).containsExactly("c2");
        assertThat(c1.replies().get(0).author()).isEqualTo("둘이");
        BoardCommentDto c4 = d.comments().get(1);
        assertThat(c4.author()).isEqualTo("넷이");
        assertThat(c4.replies()).isEmpty(); // c5 삭제 제외
    }
}
