package com.fury.back.domain.board;

import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.common.moderation.ContentPolicyService;
import com.fury.back.domain.admin.AdminActionService;
import com.fury.back.domain.board.dto.AdminCreatePostRequest;
import com.fury.back.domain.board.dto.AdminUpdatePostRequest;
import com.fury.back.domain.board.dto.PostModerationRequest;
import com.fury.back.domain.user.UserRepository;
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
class BoardAdminServiceTest {

    @Mock BoardPostRepository postRepo;
    @Mock BoardCommentRepository commentRepo;
    @Mock ContentPolicyService contentPolicy;
    @Mock AdminAuthorizationService adminAuth;
    @Mock AdminActionService adminActions;
    @Mock UserRepository userRepo;
    @InjectMocks BoardAdminService service;

    private static final LocalDateTime T = LocalDateTime.of(2026, 6, 23, 10, 0);

    private BoardPost post(String id, String type, String section, String status, LocalDateTime deleted) {
        return BoardPost.builder().postId(id).type(type).section(section).title("t").content("c")
                .authorId("op").pinned(false).answered(false).viewCount(0).likeCount(0)
                .status(status).createdAt(T).deletedAt(deleted).build();
    }

    private void notEnforced() { when(adminAuth.isEnforced()).thenReturn(false); }

    // ── createOfficial ──
    @Test void createOfficial_officialType_savesWithAdminAuthor_andAudits() {
        notEnforced();
        when(userRepo.existsById("admin1")).thenReturn(true);
        when(postRepo.save(any())).thenAnswer(i -> i.getArgument(0));
        service.createOfficial("admin1", new AdminCreatePostRequest("notice", "공지", "내용", true));
        verify(postRepo).save(argThat(p ->
                p.getType().equals("notice") && p.getSection().equals("official")
                        && p.getAuthorId().equals("admin1") && p.isPinned()));
        verify(adminActions).record(eq("admin1"), eq("BOARD_POST_CREATE"), eq("BOARD_POST"), any(), any(), any(), any(), any());
    }

    @Test void createOfficial_userType_403() {
        notEnforced();
        assertThatThrownBy(() -> service.createOfficial("admin1", new AdminCreatePostRequest("free", "t", "c", null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    @Test void createOfficial_missingAdminAccount_400() {
        notEnforced();
        when(userRepo.existsById("ghost")).thenReturn(false);
        assertThatThrownBy(() -> service.createOfficial("ghost", new AdminCreatePostRequest("notice", "t", "c", null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    // ── updateOfficial: 공식글만 ──
    @Test void updateOfficial_officialPost_edits() {
        notEnforced();
        BoardPost p = post("p", "notice", "official", "ACTIVE", null);
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        service.updateOfficial("admin1", "p", new AdminUpdatePostRequest("새 공지", null, null));
        assertThat(p.getTitle()).isEqualTo("새 공지");
        verify(adminActions).record(eq("admin1"), eq("BOARD_POST_UPDATE"), any(), any(), any(), any(), any(), any());
    }

    @Test void updateOfficial_userPost_403_noContentEdit() {
        notEnforced();
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "ACTIVE", null)));
        assertThatThrownBy(() -> service.updateOfficial("admin1", "p", new AdminUpdatePostRequest("바꿔치기", null, null)))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
    }

    // ── moderatePost: 두 축 독립 (Fix 2 핵심) ──
    @Test void moderate_RESTORE_clears_deletedAt_only_keeps_status() {
        notEnforced();
        BoardPost p = post("p", "free", "community", "HIDDEN", T); // 숨김 + 삭제 상태
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        service.moderatePost("admin1", "p", new PostModerationRequest("RESTORE"));
        assertThat(p.getDeletedAt()).isNull();          // 삭제 복구
        assertThat(p.getStatus()).isEqualTo("HIDDEN");  // ★status 불변(자동 공개 안 함)
    }

    @Test void moderate_HIDE_and_UNHIDE_toggle_status_only() {
        notEnforced();
        BoardPost p = post("p", "free", "community", "ACTIVE", null);
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        service.moderatePost("admin1", "p", new PostModerationRequest("HIDE"));
        assertThat(p.getStatus()).isEqualTo("HIDDEN");
        assertThat(p.getDeletedAt()).isNull();
        service.moderatePost("admin1", "p", new PostModerationRequest("UNHIDE"));
        assertThat(p.getStatus()).isEqualTo("ACTIVE");
    }

    @Test void moderate_unknownAction_400() {
        notEnforced();
        when(postRepo.findById("p")).thenReturn(Optional.of(post("p", "free", "community", "ACTIVE", null)));
        assertThatThrownBy(() -> service.moderatePost("admin1", "p", new PostModerationRequest("BOOM")))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("400");
    }

    @Test void deletePost_softDeletes_andAudits() {
        notEnforced();
        BoardPost p = post("p", "free", "community", "ACTIVE", null);
        when(postRepo.findById("p")).thenReturn(Optional.of(p));
        service.deletePost("admin1", "p");
        assertThat(p.getDeletedAt()).isNotNull();
        verify(adminActions).record(eq("admin1"), eq("BOARD_POST_DELETE"), any(), any(), any(), any(), any(), any());
    }

    // ── requireAdmin 이중검증 ──
    @Test void enforced_nonAdmin_403() {
        when(adminAuth.isEnforced()).thenReturn(true);
        when(adminAuth.isAdmin("intruder")).thenReturn(false);
        assertThatThrownBy(() -> service.deletePost("intruder", "p"))
                .isInstanceOf(ResponseStatusException.class).hasMessageContaining("403");
        verifyNoInteractions(postRepo);
    }
}
