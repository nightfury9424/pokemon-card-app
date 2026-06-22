package com.fury.back.domain.board;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.board.dto.CreateCommentRequest;
import com.fury.back.domain.board.dto.CreatePostRequest;
import com.fury.back.domain.board.dto.UpdatePostRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * 게시판 사용자 쓰기 서비스 (Slice 2). 일반글 작성/본인글 수정·삭제/댓글·1단답글/금칙어.
 * authz 불변식: 클라 section/authorId/isAdmin 불신, section=type 서버도출, official 작성 금지(403),
 * 본인글만 수정·삭제(아니면 404 존재 비노출).
 */
@Service
@RequiredArgsConstructor
public class BoardWriteService {

    private static final int TITLE_MAX = 200;
    private static final int CONTENT_MAX = 10000;
    private static final int COMMENT_MAX = 2000;

    private final BoardPostRepository postRepository;
    private final BoardCommentRepository commentRepository;
    private final ContentFilter contentFilter;

    @Transactional
    public String createPost(String userId, CreatePostRequest req) {
        requireAuth(userId);
        String type = req.type();
        if (!BoardTaxonomy.isValidType(type)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "잘못된 게시판 타입입니다.");
        }
        if (BoardTaxonomy.isAdminType(type)) {
            // notice/event/patch 는 관리자 전용 → 사용자 작성 차단
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "공지 계열은 작성할 수 없습니다.");
        }
        String title = clean(req.title(), TITLE_MAX, "제목");
        String content = clean(req.content(), CONTENT_MAX, "내용");
        rejectBanned(title, content);

        BoardPost post = BoardPost.builder()
                .postId(IdGenerator.generate())
                .type(type)
                .section(BoardTaxonomy.sectionOf(type)) // ★서버 도출
                .title(title)
                .content(content)
                .authorId(userId)                       // ★서버 결정
                .pinned(false)
                .answered(false)
                .viewCount(0)
                .likeCount(0)
                .status("ACTIVE")
                .build();
        return postRepository.save(post).getPostId();
    }

    @Transactional
    public void updatePost(String userId, String postId, UpdatePostRequest req) {
        requireAuth(userId);
        BoardPost post = ownedVisiblePost(postId, userId);
        String title = clean(req.title(), TITLE_MAX, "제목");
        String content = clean(req.content(), CONTENT_MAX, "내용");
        rejectBanned(title, content);
        post.editContent(title, content);
    }

    @Transactional
    public void deletePost(String userId, String postId) {
        requireAuth(userId);
        ownedVisiblePost(postId, userId).softDelete();
    }

    @Transactional
    public String createComment(String userId, String postId, CreateCommentRequest req) {
        requireAuth(userId);
        // 대상 게시글은 ACTIVE & 미삭제여야(아니면 404 존재 비노출)
        postRepository.findById(postId)
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));

        String content = clean(req.content(), COMMENT_MAX, "댓글");
        rejectBanned(content);

        String parentId = req.parentCommentId();
        if (parentId != null) {
            BoardComment parent = commentRepository.findById(parentId)
                    .orElseThrow(() -> new ResponseStatusException(HttpStatus.BAD_REQUEST, "원 댓글을 찾을 수 없습니다."));
            if (!parent.getPostId().equals(postId)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "다른 게시글의 댓글에는 답글을 달 수 없습니다.");
            }
            if (!parent.isTopLevel()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "답글에는 다시 답글을 달 수 없습니다.");
            }
            if (parent.isDeleted()) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "삭제된 댓글에는 답글을 달 수 없습니다.");
            }
        }

        BoardComment comment = BoardComment.builder()
                .commentId(IdGenerator.generate())
                .postId(postId)
                .parentCommentId(parentId)
                .authorId(userId)
                .content(content)
                .admin(false)
                .accepted(false)
                .build();
        return commentRepository.save(comment).getCommentId();
    }

    @Transactional
    public void deleteComment(String userId, String commentId) {
        requireAuth(userId);
        BoardComment c = commentRepository.findById(commentId)
                .filter(x -> !x.isDeleted())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "댓글을 찾을 수 없습니다."));
        if (!c.getAuthorId().equals(userId)) {
            // 타인 댓글 → 존재 비노출
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "댓글을 찾을 수 없습니다.");
        }
        c.softDelete();
    }

    // ── helpers ──

    private void requireAuth(String userId) {
        if (userId == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "로그인이 필요합니다.");
        }
    }

    /** 본인 소유 + 노출(ACTIVE·미삭제) 게시글. 아니면 404(존재 비노출). */
    private BoardPost ownedVisiblePost(String postId, String userId) {
        BoardPost post = postRepository.findById(postId)
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        if (!post.getAuthorId().equals(userId)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다.");
        }
        return post;
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
            if (contentFilter.containsBanned(t)) {
                throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "부적절한 표현이 포함되어 있습니다.");
            }
        }
    }
}
