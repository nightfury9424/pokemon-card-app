package com.fury.back.domain.board;

import com.fury.back.auth.AdminAuthorizationService;
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
    @Mock BoardImageUploadRepository imageUploadRepo;
    @Mock BoardPostImageRepository postImageRepo;
    @Mock AdminAuthorizationService adminAuth;
    @InjectMocks BoardWriteService service;

    private BoardImageUpload upload(String id, String owner, String status, LocalDateTime expires) {
        return BoardImageUpload.builder().uploadId(id).uploaderId(owner)
                .storageKey("uploads/board/pending/" + id + ".jpg")
                .status(status).createdAt(T).expiresAt(expires).build();
    }

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

    // ── 운영팀(Admin 웹) 댓글 (#13) ──
    @Test void createAdminComment_byAdmin_onOfficial_savesAdminTrue() {
        when(adminAuth.isAdmin("admin1")).thenReturn(true);
        when(postRepo.findById("n")).thenReturn(Optional.of(post("n", "notice", "official", "admin1", "ACTIVE", null)));
        when(commentRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        service.createAdminComment("admin1", "n", new CreateCommentRequest("운영팀 공지 댓글", null));
        ArgumentCaptor<BoardComment> cap = ArgumentCaptor.forClass(BoardComment.class);
        verify(commentRepo).save(cap.capture());
        assertThat(cap.getValue().isAdmin()).isTrue();          // ★앱에서 운영팀 표시
        assertThat(cap.getValue().getAuthorId()).isEqualTo("admin1");
    }

    @Test void createAdminComment_nonAdmin_403_noSave() {
        when(adminAuth.isAdmin("u2")).thenReturn(false);
        assertThatThrownBy(() -> service.createAdminComment("u2", "n", new CreateCommentRequest("x", null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
        verify(commentRepo, never()).save(any());
    }

    @Test void createAdminComment_replyToUserComment_savesAdminTrue() {
        when(adminAuth.isAdmin("admin1")).thenReturn(true);
        when(postRepo.findById("n")).thenReturn(Optional.of(post("n", "notice", "official", "admin1", "ACTIVE", null)));
        when(commentRepo.findById("uc")).thenReturn(Optional.of(comment("uc", "n", null, "u1", false)));
        when(commentRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        service.createAdminComment("admin1", "n", new CreateCommentRequest("운영팀 답글", "uc"));
        ArgumentCaptor<BoardComment> cap = ArgumentCaptor.forClass(BoardComment.class);
        verify(commentRepo).save(cap.capture());
        assertThat(cap.getValue().isAdmin()).isTrue();
        assertThat(cap.getValue().getParentCommentId()).isEqualTo("uc");
    }

    @Test void createComment_regular_savesAdminFalse() { // 회귀: 일반 댓글은 그대로 admin=false
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        when(commentRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        service.createComment("u2", "p", new CreateCommentRequest("안녕하세요", null));
        ArgumentCaptor<BoardComment> cap = ArgumentCaptor.forClass(BoardComment.class);
        verify(commentRepo).save(cap.capture());
        assertThat(cap.getValue().isAdmin()).isFalse();
    }

    // ── createPost ──
    @Test void createPost_userType_derives_section_and_author() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        ArgumentCaptor<BoardPost> cap = ArgumentCaptor.forClass(BoardPost.class);
        service.createPost("u1", new CreatePostRequest("free", "제목", "본문"));
        verify(postRepo).save(cap.capture());
        BoardPost saved = cap.getValue();
        assertThat(saved.getSection()).isEqualTo("community"); // 서버 도출
        assertThat(saved.getType()).isEqualTo("free");
        assertThat(saved.getAuthorId()).isEqualTo("u1");       // 서버 결정
        assertThat(saved.getStatus()).isEqualTo("ACTIVE");
    }

    @Test void createPost_tradeReviewOrScamAlert_403() {
        // ★최종 IA: 사용자 작성 = 자유(free)만. 거래후기·사기주의는 차단(앱 UI 제거 + 서버 allowlist=free).
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("tradeReview", "t", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("scamAlert", "t", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    @Test void createPost_officialType_403() {
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("notice", "t", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    @Test void createPost_qnaType_403() {
        // ★qna 는 유효 타입이나 사용자 작성 allowlist(free/tradeReview/scamAlert) 밖 → 403 (직접 호출 우회 차단).
        assertThatThrownBy(() -> service.createPost("u1", new CreatePostRequest("qna", "t", "c")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    // ── createPost 이미지 연결(uploadId 소유권·일회성) ──
    @Test void createPost_validUpload_attachesImage() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        when(imageUploadRepo.findAllByUploadIdIn(any()))
                .thenReturn(java.util.List.of(upload("up1", "u1", "PENDING", LocalDateTime.now().plusHours(1))));
        service.createPost("u1", new CreatePostRequest("free", "제목", "본문", java.util.List.of("up1")));
        verify(postImageRepo).save(any()); // board_post_images 연결됨
    }

    @Test void createPost_otherUserUpload_400() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        when(imageUploadRepo.findAllByUploadIdIn(any()))
                .thenReturn(java.util.List.of(upload("up1", "other", "PENDING", LocalDateTime.now().plusHours(1))));
        assertThatThrownBy(() -> service.createPost("u1",
                new CreatePostRequest("free", "t", "c", java.util.List.of("up1"))))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
        verify(postImageRepo, never()).save(any());
    }

    @Test void createPost_consumedUpload_400() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        when(imageUploadRepo.findAllByUploadIdIn(any()))
                .thenReturn(java.util.List.of(upload("up1", "u1", "CONSUMED", LocalDateTime.now().plusHours(1))));
        assertThatThrownBy(() -> service.createPost("u1",
                new CreatePostRequest("free", "t", "c", java.util.List.of("up1"))))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void createPost_expiredUpload_400() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        when(imageUploadRepo.findAllByUploadIdIn(any()))
                .thenReturn(java.util.List.of(upload("up1", "u1", "PENDING", LocalDateTime.now().minusHours(1))));
        assertThatThrownBy(() -> service.createPost("u1",
                new CreatePostRequest("free", "t", "c", java.util.List.of("up1"))))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void createPost_tooManyImages_400() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        assertThatThrownBy(() -> service.createPost("u1",
                new CreatePostRequest("free", "t", "c", java.util.List.of("a", "b", "c", "d", "e", "f"))))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void createPost_dupUpload_400() {
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        assertThatThrownBy(() -> service.createPost("u1",
                new CreatePostRequest("free", "t", "c", java.util.List.of("up1", "up1"))))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void updatePost_otherPostExistingImage_400() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        when(postImageRepo.findByPostIdOrderBySortOrderAsc("p")).thenReturn(java.util.List.of()); // 이 글엔 이미지 없음
        var items = java.util.List.of(new UpdatePostRequest.ImageItem("other-post-img", null)); // 타 게시글 imageId
        assertThatThrownBy(() -> service.updatePost("u1", "p", new UpdatePostRequest("제목", "본문", items)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
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
        verify(postRepo, never()).save(any()); // Gate 4: 금칙어 위반 → 저장 미호출
    }

    // ── Gate 4: 금칙어 위반 시 저장·엔티티 변경 미호출 증명 ──
    @Test void updatePost_banned_doesNotMutateEntity() {
        BoardPost p = post("p", "free", "community", "u1", "ACTIVE", null); // title=t, content=c
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        doThrow(new ContentPolicyViolationException("x")).when(contentPolicy).check(any());
        assertThatThrownBy(() -> service.updatePost("u1", "p", new UpdatePostRequest("새 제목", "비속어")))
                .isInstanceOf(ContentPolicyViolationException.class);
        // editContent 미호출 증명(상태 불변).
        assertThat(p.getTitle()).isEqualTo("t");
        assertThat(p.getContent()).isEqualTo("c");
        assertThat(p.getUpdatedAt()).isNull();
        verify(postRepo, never()).save(any());
    }

    @Test void createComment_banned_doesNotSave() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        doThrow(new ContentPolicyViolationException("x")).when(contentPolicy).check(any());
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("비속어", null)))
                .isInstanceOf(ContentPolicyViolationException.class);
        verify(commentRepo, never()).save(any());
    }

    @Test void createReply_banned_doesNotSave() {
        // 답글(parentCommentId 지정)도 금칙어 검사가 부모 조회보다 먼저 → 부모 조회 도달 전 차단·저장 미호출.
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "u1", "ACTIVE", null)));
        doThrow(new ContentPolicyViolationException("x")).when(contentPolicy).check(any());
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("비속어", "parent")))
                .isInstanceOf(ContentPolicyViolationException.class);
        verify(commentRepo, never()).save(any());
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

    // ── ★1.0.4: 공식(official: notice/event/patch) 글 댓글 허용. qna 는 계속 차단 ──
    @Test void createComment_onOfficialPost_ok() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "notice", "official", "admin", "ACTIVE", null)));
        when(commentRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        service.createComment("u2", "p", new CreateCommentRequest("댓글", null));
        verify(commentRepo).save(any()); // ★공식글 댓글 허용
    }

    @Test void createComment_onPatchOfficialPost_ok() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "patch", "official", "admin", "ACTIVE", null)));
        when(commentRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        service.createComment("u2", "p", new CreateCommentRequest("댓글", null));
        verify(commentRepo).save(any());
    }

    @Test void createComment_onQnaPost_403() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "qna", "qna", "u1", "ACTIVE", null)));
        assertThatThrownBy(() -> service.createComment("u2", "p", new CreateCommentRequest("댓글", null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
        verify(commentRepo, never()).save(any());
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
