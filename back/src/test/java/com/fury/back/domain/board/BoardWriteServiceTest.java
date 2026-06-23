package com.fury.back.domain.board;

import com.fury.back.common.moderation.ContentPolicyService;
import com.fury.back.common.moderation.ContentPolicyViolationException;
import com.fury.back.domain.board.dto.CreateCommentRequest;
import com.fury.back.domain.board.dto.CreatePostRequest;
import com.fury.back.domain.board.dto.UpdatePostRequest;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BoardWriteServiceTest {

    @Mock BoardPostRepository postRepo;
    @Mock BoardCommentRepository commentRepo;
    @Mock ContentPolicyService contentPolicy;
    @InjectMocks BoardWriteService service;

    private static final LocalDateTime T = LocalDateTime.of(2026, 6, 23, 10, 0);

    private BoardPost post(String id, String type, String section, String author, String status, LocalDateTime deleted) {
        return BoardPost.builder().postId(id).type(type).section(section).title("t").content("c")
                .authorId(author).pinned(false).answered(false).viewCount(0).likeCount(0)
                .status(status).createdAt(T).deletedAt(deleted).build();
    }

    private BoardComment comment(String id, String postId, String parent, String author, boolean deleted) {
        return BoardComment.builder().commentId(id).postId(postId).parentCommentId(parent).authorId(author)
                .content("c").admin(false).accepted(false).createdAt(T).deletedAt(deleted ? T : null).build();
    }

    // ── createPost ──
    @Test void createPost_userType_derives_section_and_author() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        ArgumentCaptor<BoardPost> cap = ArgumentCaptor.forClass(BoardPost.class);
        service.createPost("u1", new CreatePostRequest("tradeReview", "제목", "본문"));
        verify(postRepo).save(cap.capture());
        BoardPost saved = cap.getValue();
        assertThat(saved.getSection()).isEqualTo("community"); // 서버 도출
        assertThat(saved.getType()).isEqualTo("tradeReview");
        assertThat(saved.getAuthorId()).isEqualTo("u1");       // 서버 결정
        assertThat(saved.getStatus()).isEqualTo("ACTIVE");
    }

    @Test void createPost_officialType_403() {
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("notice", "t", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    @Test void createPost_invalidType_400() {
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("xxx", "t", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void createPost_blankTitle_400() {
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("free", "  ", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void createPost_banned_blocked() {
        doThrow(new ContentPolicyViolationException("x")).when(contentPolicy).check(any());
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("free", "t", "비속어")))
                .isInstanceOf(ContentPolicyViolationException.class);
    }

    @Test void createPost_unauthenticated_401() {
        assertThatThrownBy(() -> service.createPost(null, new CreatePostRequest("free", "t", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("401");
    }

    // ── updatePost ──
    @Test void updatePost_owner_edits() {
        BoardPost p = post("p", "free", "community", "u1", "ACTIVE", null);
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        service.updatePost("u1", "p", new UpdatePostRequest("새 제목", "새 본문"));
        assertThat(p.getTitle()).isEqualTo("새 제목");
        assertThat(p.getUpdatedAt()).isNotNull();
    }

    @Test void updatePost_nonOwner_404() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "owner", "ACTIVE", null)));
        assertThatThrownBy(() -> service.updatePost("intruder", "p", new UpdatePostRequest("a", "b")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void updatePost_deleted_404() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", T)));
        assertThatThrownBy(() -> service.updatePost("u1", "p", new UpdatePostRequest("a", "b")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    // ── createComment ──
    @Test void createComment_topLevel_ok() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        when(commentRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        service.createComment("u2", "p", new CreateCommentRequest("댓글", null));
        verify(commentRepo).save(any());
    }

    // ── 공지(official) 글 댓글·대댓글 작성 거부(모든 사용자) ──
    @Test void createComment_onOfficialPost_403() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "notice", "official", "admin", "ACTIVE", null)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("댓글", null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
        verify(commentRepo, never()).save(any());
    }

    @Test void createReply_onOfficialPost_403() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "event", "official", "admin", "ACTIVE", null)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("답글", "parentX")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
        verify(commentRepo, never()).save(any());
    }

    @Test void createComment_onPatchOfficialPost_403() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "patch", "official", "admin", "ACTIVE", null)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("댓글", null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    @Test void createComment_onHiddenPost_404() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "HIDDEN", null)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("c", null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void createComment_reply_parentDifferentPost_400() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        when(commentRepo.findById("parent")).thenReturn(Optional.of(comment("parent", "OTHER", null, "x", false)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("c", "parent")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void createComment_replyToReply_400() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        when(commentRepo.findById("parent")).thenReturn(Optional.of(comment("parent", "p", "grandparent", "x", false)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("c", "parent")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void createComment_deletedParent_400() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        when(commentRepo.findById("parent")).thenReturn(Optional.of(comment("parent", "p", null, "x", true)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("c", "parent")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    // ── deleteComment ──
    @Test void deleteComment_owner_softDeletes() {
        BoardComment c = comment("c1", "p", null, "u2", false);
        when(commentRepo.findById("c1")).thenReturn(Optional.of(c));
        service.deleteComment("u2", "c1");
        assertThat(c.isDeleted()).isTrue();
    }

    @Test void deleteComment_nonOwner_404() {
        when(commentRepo.findById("c1")).thenReturn(Optional.of(comment("c1", "p", null, "owner", false)));
        assertThatThrownBy(() -> service.deleteComment("intruder", "c1"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }
}
