package com.fury.back.domain.board;

import com.fury.back.domain.block.Block;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.board.dto.BoardCommentDto;
import com.fury.back.domain.board.dto.BoardPostDetailDto;
import com.fury.back.domain.board.dto.BoardPostSummaryDto;
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

    // ── 개인 차단: 뷰어가 차단한 author 의 댓글·대댓글 상세 응답에서 서버 필터 ──
    @Test void detail_filters_blocked_author_comments_for_viewer() {
        when(postRepo.findById("p")).thenReturn(Optional.of(active("p", "free", "community", "u1")));
        when(blockRepo.existsByBlockerIdAndBlockedId("viewer", "u1")).thenReturn(false); // 글 author 는 미차단
        Block bk = mock(Block.class);
        when(bk.getBlockedId()).thenReturn("bx"); // 뷰어가 bx 차단
        when(blockRepo.findAllByBlockerId("viewer")).thenReturn(List.of(bk));
        when(commentRepo.findByPostIdOrderByCreatedAtAsc("p")).thenReturn(List.of(
                c("c1", null, "u2", false, false), // 보임
                c("c2", null, "bx", false, false), // 차단 author 최상위 → 제외
                c("c3", "c2", "u3", false, false), // 차단 최상위의 답글 → 부모 사라져 제외
                c("c4", "c1", "bx", false, false)  // 비차단 최상위(c1)에 달린 차단 author 답글 → 제외
        ));
        User u2 = mock(User.class); when(u2.getUserId()).thenReturn("u2"); when(u2.getNickname()).thenReturn("둘");
        when(userRepo.findAllById(anySet())).thenReturn(List.of(u2));

        BoardPostDetailDto d = service.getDetail("p", "viewer");

        assertThat(d.comments()).extracting(BoardCommentDto::id).containsExactly("c1");
        assertThat(d.comments().get(0).replies()).isEmpty(); // c4(bx 답글) 제외
        assertThat(d.commentCount()).isEqualTo(1); // c1 만(c2/c3/c4 차단 제외)
    }

    // ── 소유권·액션 플래그 연결(상세) ──
    @Test void detail_wires_post_and_comment_flags() {
        when(postRepo.findById("p")).thenReturn(Optional.of(active("p", "free", "community", "author1")));
        when(blockRepo.existsByBlockerIdAndBlockedId("viewer", "author1")).thenReturn(false);
        when(blockRepo.findAllByBlockerId("viewer")).thenReturn(List.of());
        when(commentRepo.findByPostIdOrderByCreatedAtAsc("p")).thenReturn(List.of(
                c("mineTop", null, "viewer", false, false),  // 본인 최상위
                c("otherTop", null, "uX", false, false),     // 타인 최상위
                c("oReply", "otherTop", "uY", false, false), // 타인 대댓글
                c("adminTop", null, "adminU", false, true)   // 운영 뱃지 댓글
        ));
        when(userRepo.findAllById(anySet())).thenReturn(List.of());

        BoardPostDetailDto d = service.getDetail("p", "viewer");

        // 게시글: 타인 자유글 → 신고/차단 O, 수정/삭제 X
        assertThat(d.mine()).isFalse();
        assertThat(d.canEdit()).isFalse();
        assertThat(d.canReport()).isTrue();
        assertThat(d.canBlock()).isTrue();

        BoardCommentDto mineTop = find(d.comments(), "mineTop");
        assertThat(mineTop.mine()).isTrue();
        assertThat(mineTop.canDelete()).isTrue();
        assertThat(mineTop.canReply()).isTrue();
        assertThat(mineTop.replyTargetCommentId()).isEqualTo("mineTop");
        assertThat(mineTop.canReport()).isFalse();

        BoardCommentDto otherTop = find(d.comments(), "otherTop");
        assertThat(otherTop.mine()).isFalse();
        assertThat(otherTop.canReport()).isTrue();
        assertThat(otherTop.canBlock()).isTrue();
        assertThat(otherTop.canReply()).isTrue();
        BoardCommentDto oReply = otherTop.replies().get(0);
        assertThat(oReply.id()).isEqualTo("oReply");
        assertThat(oReply.replyTargetCommentId()).isEqualTo("otherTop"); // ★최상위 부모
        assertThat(oReply.canReport()).isTrue();

        BoardCommentDto adminTop = find(d.comments(), "adminTop");
        assertThat(adminTop.isAdmin()).isTrue();
        assertThat(adminTop.canReport()).isTrue(); // ★운영 뱃지여도 신고 가능(면제 없음)
        assertThat(adminTop.canBlock()).isTrue();
    }

    // ── 목록 vs 상세 플래그 일치(공통 헬퍼) ──
    @Test void summary_and_detail_post_flags_consistent() {
        BoardPost p = active("p", "free", "community", "author1");
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        when(blockRepo.existsByBlockerIdAndBlockedId("viewer", "author1")).thenReturn(false);
        when(blockRepo.findAllByBlockerId("viewer")).thenReturn(List.of());
        when(commentRepo.findByPostIdOrderByCreatedAtAsc("p")).thenReturn(List.of());
        when(postRepo.findFeed(any(), any(), eq("viewer"), any())).thenReturn(new PageImpl<>(List.of(p)));
        when(commentRepo.countActiveByPostIds(anyList())).thenReturn(List.of());
        when(userRepo.findAllById(anySet())).thenReturn(List.of());

        BoardPostDetailDto d = service.getDetail("p", "viewer");
        BoardPostSummaryDto s = service.getFeed(null, null, "viewer", 0, 20).content().get(0);

        assertThat(s.mine()).isEqualTo(d.mine());
        assertThat(s.canEdit()).isEqualTo(d.canEdit());
        assertThat(s.canDelete()).isEqualTo(d.canDelete());
        assertThat(s.canReport()).isEqualTo(d.canReport());
        assertThat(s.canBlock()).isEqualTo(d.canBlock());
    }

    private static BoardCommentDto find(List<BoardCommentDto> list, String id) {
        return list.stream().filter(x -> x.id().equals(id)).findFirst().orElseThrow();
    }
}
