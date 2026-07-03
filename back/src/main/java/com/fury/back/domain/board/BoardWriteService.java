package com.fury.back.domain.board;

import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.common.IdGenerator;
import com.fury.back.domain.board.event.BoardCommentCreatedEvent;
import org.springframework.context.ApplicationEventPublisher;
import com.fury.back.common.moderation.ContentPolicyService;
import com.fury.back.domain.board.dto.CreateCommentRequest;
import com.fury.back.domain.board.dto.CreatePostRequest;
import com.fury.back.domain.board.dto.UpdatePostRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

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
    private static final int MAX_IMAGES = 5;

    private final BoardPostRepository postRepository;
    private final ApplicationEventPublisher eventPublisher;
    private final BoardCommentRepository commentRepository;
    private final ContentPolicyService contentPolicy;
    private final BoardImageUploadRepository imageUploadRepository;
    private final BoardPostImageRepository postImageRepository;
    private final AdminAuthorizationService adminAuth;

    @Transactional
    public String createPost(String userId, CreatePostRequest req) {
        requireAuth(userId);
        String type = req.type();
        if (!BoardTaxonomy.isValidType(type)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "잘못된 게시판 타입입니다.");
        }
        // ★allowlist — 자유/거래후기/사기주의만 허용. 공식(notice/event/patch)·qna 는 직접 호출도 403.
        if (!BoardTaxonomy.isUserWritableType(type)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "작성할 수 없는 게시판 타입입니다.");
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
        String postId = postRepository.save(post).getPostId();
        attachUploadsForCreate(postId, userId, req.imageUploadIds());
        return postId;
    }

    // ───────────────────────── 이미지 연결(uploadId → board_post_images) ─────────────────────────

    /** 작성 — uploadId 검증(소유자·PENDING·미만료·중복없음·최대5) 후 연결 + upload CONSUMED. createPost tx 내(실패 시 전체 롤백). */
    private void attachUploadsForCreate(String postId, String userId, List<String> uploadIds) {
        if (uploadIds == null || uploadIds.isEmpty()) return;
        if (new HashSet<>(uploadIds).size() != uploadIds.size()) throw badReq("중복된 이미지입니다.");
        if (uploadIds.size() > MAX_IMAGES) throw badReq("이미지는 최대 " + MAX_IMAGES + "장까지 첨부할 수 있습니다.");
        LocalDateTime now = LocalDateTime.now();
        Map<String, BoardImageUpload> byId = imageUploadRepository.findAllByUploadIdIn(uploadIds).stream()
                .collect(Collectors.toMap(BoardImageUpload::getUploadId, u -> u));
        int order = 0;
        for (String uid : uploadIds) {
            BoardImageUpload u = validUpload(byId.get(uid), userId, now);
            savePostImage(postId, u.getStorageKey(), order++, now);
            u.consume(postId, now);
        }
    }

    /** 수정 — 최종 순서(기존 imageId 유지 / 신규 uploadId)로 재구성. 제거 이미지 S3 객체는 보존(신고 증거). */
    private void rebuildImages(String postId, String userId, List<UpdatePostRequest.ImageItem> items) {
        if (items == null) return; // null = 이미지 미변경(기존 유지)
        if (items.size() > MAX_IMAGES) throw badReq("이미지는 최대 " + MAX_IMAGES + "장까지 첨부할 수 있습니다.");
        LocalDateTime now = LocalDateTime.now();
        Map<String, BoardPostImage> currentById = postImageRepository.findByPostIdOrderBySortOrderAsc(postId).stream()
                .collect(Collectors.toMap(BoardPostImage::getImageId, i -> i));
        List<String> finalKeys = new ArrayList<>();
        List<BoardImageUpload> toConsume = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (UpdatePostRequest.ImageItem it : items) {
            boolean hasExisting = it.existingImageId() != null && !it.existingImageId().isBlank();
            boolean hasUpload = it.uploadId() != null && !it.uploadId().isBlank();
            if (hasExisting == hasUpload) throw badReq("이미지 항목이 올바르지 않습니다.");
            if (hasExisting) {
                if (!seen.add("e:" + it.existingImageId())) throw badReq("중복된 이미지입니다.");
                BoardPostImage cur = currentById.get(it.existingImageId());
                if (cur == null) throw badReq("이 게시글의 이미지가 아닙니다."); // ★타 게시글 imageId 우회 차단
                finalKeys.add(cur.getStorageKey());
            } else {
                if (!seen.add("u:" + it.uploadId())) throw badReq("중복된 이미지입니다.");
                BoardImageUpload u = validUpload(imageUploadRepository.findById(it.uploadId()).orElse(null), userId, now);
                finalKeys.add(u.getStorageKey());
                toConsume.add(u);
            }
        }
        // 전삭제 → 재삽입(UNIQUE(post_id,sort_order)·UNIQUE(storage_key) 충돌 회피). 제거분 S3 미삭제(보존).
        postImageRepository.deleteByPostId(postId);
        postImageRepository.flush();
        for (int i = 0; i < finalKeys.size(); i++) savePostImage(postId, finalKeys.get(i), i, now);
        for (BoardImageUpload u : toConsume) u.consume(postId, now);
    }

    private BoardImageUpload validUpload(BoardImageUpload u, String userId, LocalDateTime now) {
        if (u == null || !u.getUploaderId().equals(userId) || !u.isPending() || u.isExpired(now)) {
            throw badReq("유효하지 않은 이미지입니다.");
        }
        return u;
    }

    private void savePostImage(String postId, String storageKey, int order, LocalDateTime now) {
        postImageRepository.save(BoardPostImage.builder()
                .imageId(IdGenerator.generate()).postId(postId)
                .storageKey(storageKey).sortOrder(order).createdAt(now).build());
    }

    private static ResponseStatusException badReq(String msg) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, msg);
    }

    @Transactional
    public void updatePost(String userId, String postId, UpdatePostRequest req) {
        requireAuth(userId);
        BoardPost post = ownedVisiblePost(postId, userId);
        String title = clean(req.title(), TITLE_MAX, "제목");
        String content = clean(req.content(), CONTENT_MAX, "내용");
        rejectBanned(title, content);
        post.editContent(title, content);
        rebuildImages(postId, userId, req.images());
    }

    @Transactional
    public void deletePost(String userId, String postId) {
        requireAuth(userId);
        ownedVisiblePost(postId, userId).softDelete();
    }

    @Transactional
    public String createComment(String userId, String postId, CreateCommentRequest req) {
        requireAuth(userId);
        return createCommentInternal(userId, postId, req, false);
    }

    /** ★운영팀(Admin 웹) 공지/게시글 댓글·대댓글 — admin=true 로 저장(앱에서 '운영팀' 표시·차단불가). 엔드포인트는 admin-gated. */
    @Transactional
    public String createAdminComment(String adminUserId, String postId, CreateCommentRequest req) {
        if (adminUserId == null || !adminAuth.isAdmin(adminUserId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "관리자 권한이 필요합니다.");
        }
        return createCommentInternal(adminUserId, postId, req, true);
    }

    private String createCommentInternal(String userId, String postId, CreateCommentRequest req, boolean asAdmin) {
        // 대상 게시글은 ACTIVE & 미삭제여야(아니면 404 존재 비노출)
        BoardPost post = postRepository.findById(postId)
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        // ★1.0.4: 노출 타입(notice/event/patch/free)에 댓글·대댓글 허용 — 공지계열 포함. qna/그 외=차단.
        if (!BoardTaxonomy.isBoardVisibleType(post.getType())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "댓글을 작성할 수 없는 게시글입니다.");
        }
        // ★운영팀(Admin 웹) 댓글·대댓글은 공식 게시글(notice/event/patch)에만. 일반글(free 등)은 Admin endpoint 로 작성 금지(서버 강제).
        if (asAdmin && !BoardTaxonomy.isAdminType(post.getType())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "운영팀 댓글은 공식 게시글에만 작성할 수 있습니다.");
        }

        String content = clean(req.content(), COMMENT_MAX, "댓글");
        rejectBanned(content); // ★운영팀 댓글도 동일하게 콘텐츠 정책 적용(admin=true 표시·차단불가와는 별개 — 면제 아님)

        String parentId = req.parentCommentId();
        String parentAuthorId = null;
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
            parentAuthorId = parent.getAuthorId();
        }

        BoardComment comment = BoardComment.builder()
                .commentId(IdGenerator.generate())
                .postId(postId)
                .parentCommentId(parentId)
                .authorId(userId)
                .content(content)
                .admin(asAdmin)
                .accepted(false)
                .build();
        String savedId = commentRepository.save(comment).getCommentId();
        // 댓글/대댓글 알림(AFTER_COMMIT) — DB commit 후 게시글 작성자/부모 댓글 작성자에게.
        eventPublisher.publishEvent(new BoardCommentCreatedEvent(
                postId, savedId, userId, post.getAuthorId(), parentId, parentAuthorId));
        return savedId;
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

    // 공용 금칙어 검사(위반 시 ContentPolicyViolationException → 403 + CONTENT_POLICY_VIOLATION).
    private void rejectBanned(String... texts) {
        for (String t : texts) {
            contentPolicy.check(t);
        }
    }
}
