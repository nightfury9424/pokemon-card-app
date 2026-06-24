package com.fury.back.domain.board;

import com.fury.back.domain.board.dto.BoardLikeResponse;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class BoardLikeServiceTest {

    @Mock BoardPostRepository postRepo;
    @Mock BoardPostLikeRepository likeRepo;
    @InjectMocks BoardLikeService service;

    private static final LocalDateTime T = LocalDateTime.of(2026, 6, 24, 10, 0);

    private BoardPost post(String type, String status, String author, LocalDateTime deleted) {
        return BoardPost.builder().postId("p").type(type).section("community").title("t").content("c")
                .authorId(author).status(status).createdAt(T).deletedAt(deleted).build();
    }

    @Test void like_new_returns_true_and_count() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("free", "ACTIVE", "author", null)));
        when(likeRepo.countByPostId("p")).thenReturn(1L);
        BoardLikeResponse r = service.like("u1", "p");
        assertThat(r.likedByMe()).isTrue();
        assertThat(r.likeCount()).isEqualTo(1);
        verify(likeRepo).insertIgnore(anyString(), eq("p"), eq("u1"));
    }

    @Test void like_duplicate_idempotent_still_true() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("free", "ACTIVE", "author", null)));
        when(likeRepo.insertIgnore(anyString(), eq("p"), eq("u1"))).thenReturn(0); // 충돌(이미 존재)
        when(likeRepo.countByPostId("p")).thenReturn(1L);
        assertThat(service.like("u1", "p").likedByMe()).isTrue();
    }

    @Test void unlike_returns_false_and_count() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("free", "ACTIVE", "author", null)));
        when(likeRepo.countByPostId("p")).thenReturn(0L);
        BoardLikeResponse r = service.unlike("u1", "p");
        assertThat(r.likedByMe()).isFalse();
        assertThat(r.likeCount()).isEqualTo(0);
        verify(likeRepo).deleteByPostIdAndUserId("p", "u1");
    }

    @Test void unlike_duplicate_idempotent() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("free", "ACTIVE", "author", null)));
        when(likeRepo.deleteByPostIdAndUserId("p", "u1")).thenReturn(0); // 없던 것
        when(likeRepo.countByPostId("p")).thenReturn(0L);
        assertThat(service.unlike("u1", "p").likedByMe()).isFalse();
    }

    @Test void like_ownPost_allowed() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("free", "ACTIVE", "u1", null))); // author=viewer
        when(likeRepo.countByPostId("p")).thenReturn(1L);
        assertThat(service.like("u1", "p").likedByMe()).isTrue(); // 본인 글 허용
    }

    @Test void like_unauthenticated_401() {
        assertThatThrownBy(() -> service.like(null, "p"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("401");
    }

    @Test void like_missing_404() {
        when(postRepo.findById("p")).thenReturn(Optional.empty());
        assertThatThrownBy(() -> service.like("u1", "p"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void like_hidden_404() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("free", "HIDDEN", "author", null)));
        assertThatThrownBy(() -> service.like("u1", "p"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void like_deleted_404() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("free", "ACTIVE", "author", T)));
        assertThatThrownBy(() -> service.like("u1", "p"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("404");
    }

    @Test void like_official_allowed() {
        // ★1.0.4: 공식글(notice/event/patch)도 좋아요 허용
        when(postRepo.findById("p")).thenReturn(Optional.of(post("notice", "ACTIVE", "author", null)));
        when(likeRepo.countByPostId("p")).thenReturn(1L);
        BoardLikeResponse r = service.like("u1", "p");
        assertThat(r.likedByMe()).isTrue();
        assertThat(r.likeCount()).isEqualTo(1);
    }

    @Test void like_nonFree_community_type_403() {
        when(postRepo.findById("p")).thenReturn(Optional.of(post("tradeReview", "ACTIVE", "author", null)));
        assertThatThrownBy(() -> service.like("u1", "p"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403"); // free 외 거부
    }
}
