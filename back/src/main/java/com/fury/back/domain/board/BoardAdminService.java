package com.fury.back.domain.board;

import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.common.IdGenerator;
import com.fury.back.domain.admin.AdminActionService;
import com.fury.back.domain.board.dto.AdminCreatePostRequest;
import com.fury.back.domain.board.dto.AdminUpdatePostRequest;
import com.fury.back.domain.board.dto.PostModerationRequest;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * 게시판 관리자 서비스 (Slice 2). 공식글(notice/event/patch) 작성·수정·삭제 + 일반글/댓글 모더레이션 + 감사로그.
 * ★사용자 글 내용 임의수정 금지(모더레이션만). authz 는 필터 + 본 서비스 재검증(이중, SSOT=AdminAuthorizationService).
 */
@Service
@RequiredArgsConstructor
public class BoardAdminService {

    private static final int TITLE_MAX = 200;
    private static final int CONTENT_MAX = 10000;

    private final BoardPostRepository postRepository;
    private final BoardCommentRepository commentRepository;
    private final ContentFilter contentFilter;
    private final AdminAuthorizationService adminAuthorizationService;
    private final AdminActionService adminActionService;
    private final UserRepository userRepository;

    @Transactional
    public String createOfficial(String adminUserId, AdminCreatePostRequest req) {
        requireAdmin(adminUserId);
        String type = req.type();
        if (!BoardTaxonomy.isValidType(type)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "잘못된 게시판 타입입니다.");
        }
        if (!BoardTaxonomy.isAdminType(type)) {
            // 공식글 API 는 notice/event/patch 만
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "공식 게시판 타입만 작성할 수 있습니다.");
        }
        // author = 인증된 관리자 실 userId. 운영 계정 row 미존재면 작성 실패(합성 계정 하드코딩 금지).
        if (!userRepository.existsById(adminUserId)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "관리자 계정을 찾을 수 없습니다.");
        }
        String title = clean(req.title(), TITLE_MAX, "제목");
        String content = clean(req.content(), CONTENT_MAX, "내용");
        rejectBanned(title, content);

        BoardPost post = BoardPost.builder()
                .postId(IdGenerator.generate())
                .type(type)
                .section(BoardTaxonomy.sectionOf(type))
                .title(title)
                .content(content)
                .authorId(adminUserId)                  // ★서버 결정(요청 authorId 무시), 표시명은 "운영팀"
                .pinned(Boolean.TRUE.equals(req.isPinned()))
                .answered(false)
                .viewCount(0)
                .likeCount(0)
                .status("ACTIVE")
                .build();
        String id = postRepository.save(post).getPostId();
        audit(adminUserId, "BOARD_POST_CREATE", id, null, "ACTIVE");
        return id;
    }

    @Transactional
    public void updateOfficial(String adminUserId, String postId, AdminUpdatePostRequest req) {
        requireAdmin(adminUserId);
        BoardPost post = post(postId);
        // ★공식글만 내용 수정 가능. 사용자 글은 모더레이션만(내용 임의수정 금지).
        if (!BoardTaxonomy.isAdminType(post.getType())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "사용자 게시글 내용은 수정할 수 없습니다.");
        }
        String title = req.title() == null ? null : clean(req.title(), TITLE_MAX, "제목");
        String content = req.content() == null ? null : clean(req.content(), CONTENT_MAX, "내용");
        rejectBanned(title, content);
        post.adminEdit(title, content, req.isPinned());
        audit(adminUserId, "BOARD_POST_UPDATE", postId, null, null);
    }

    @Transactional
    public void deletePost(String adminUserId, String postId) {
        requireAdmin(adminUserId);
        BoardPost post = post(postId);
        post.softDelete();
        audit(adminUserId, "BOARD_POST_DELETE", postId, "ACTIVE", "DELETED");
    }

    @Transactional
    public void moderatePost(String adminUserId, String postId, PostModerationRequest req) {
        requireAdmin(adminUserId);
        BoardPost post = post(postId);
        String action = req.action();
        if (action == null) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "action 이 필요합니다.");
        }
        switch (action) {
            case "HIDE" -> post.hide();
            case "UNHIDE" -> post.unhide();
            case "RESTORE" -> post.restore(); // ★deleted_at 만 클리어, status 불변
            default -> throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "알 수 없는 action 입니다.");
        }
        audit(adminUserId, "BOARD_POST_MODERATE_" + action, postId, null, null);
    }

    @Transactional
    public void deleteComment(String adminUserId, String commentId) {
        requireAdmin(adminUserId);
        BoardComment c = comment(commentId);
        c.softDelete();
        audit(adminUserId, "BOARD_COMMENT_DELETE", commentId, "ACTIVE", "DELETED");
    }

    @Transactional
    public void restoreComment(String adminUserId, String commentId) {
        requireAdmin(adminUserId);
        BoardComment c = comment(commentId);
        c.restore();
        audit(adminUserId, "BOARD_COMMENT_RESTORE", commentId, "DELETED", "ACTIVE");
    }

    // ── helpers ──

    /** 서비스 계층 재검증(이중). enforce 시에만 차단 — local permitAll 편의는 필터와 동일하게 보존. */
    private void requireAdmin(String userId) {
        if (adminAuthorizationService.isEnforced() && !adminAuthorizationService.isAdmin(userId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "관리자 권한이 필요합니다.");
        }
    }

    private BoardPost post(String postId) {
        return postRepository.findById(postId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
    }

    private BoardComment comment(String commentId) {
        return commentRepository.findById(commentId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "댓글을 찾을 수 없습니다."));
    }

    private void audit(String adminUserId, String actionType, String targetId,
                       String prev, String next) {
        String targetType = actionType.startsWith("BOARD_COMMENT") ? "BOARD_COMMENT" : "BOARD_POST";
        adminActionService.record(adminUserId, actionType, targetType, targetId, null, null, prev, next);
    }

    private String clean(String raw, int max, String field) {
        String v = raw == null ? "" : raw.trim();
        if (v.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, field + "을(를) 입력해 주세요.");
        }
        if (v.length() > max) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, field + "이(가) 너무 깁니다.");
        }
        return v;
    }

    private void rejectBanned(String... texts) {
        for (String t : texts) {
            if (t != null && contentFilter.containsBanned(t)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "부적절한 표현이 포함되어 있습니다.");
            }
        }
    }
}
