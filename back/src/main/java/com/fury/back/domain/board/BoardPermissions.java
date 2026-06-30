package com.fury.back.domain.board;

/**
 * 게시판 소유권·액션 플래그 계산 — ★목록·상세 공통 단일 진실원(불일치 차단).
 *
 * <p>원칙:
 * <ul>
 *   <li>boolean 은 UI 노출용일 뿐 — 실제 권한은 각 쓰기 API 가 다시 검증(updatePost/deletePost/createComment, 신고/차단).
 *   <li>raw authorId 는 DTO 에 노출하지 않는다(기존 BlockController "raw user_id 노출 X" 관례). viewerId 와 여기서만 비교.
 *   <li>닉네임 비교 금지 — viewerId.equals(authorId).
 *   <li>신고/차단 대상은 별도 식별자 없이 기존 postId/commentId 로 서버가 작성자 해석(엔티티 기반, 후속 슬라이스).
 * </ul>
 */
public final class BoardPermissions {

    private BoardPermissions() {}

    /** 게시글 플래그. mine 은 순수 소유(공식글이라도 본인이면 true), 단 공식글은 canEdit/Delete=false. */
    public record PostFlags(boolean mine, boolean canEdit, boolean canDelete,
                            boolean canReport, boolean canBlock) {}

    /** 댓글/대댓글 플래그. replyTargetCommentId = 항상 최상위 댓글 id(2단 이상 방지). 삭제 placeholder=모두 차단. */
    public record CommentFlags(boolean mine, boolean canDelete, boolean canReply,
                               String replyTargetCommentId, boolean canReport, boolean canBlock) {}

    private static boolean loggedIn(String viewerId) {
        return viewerId != null && !viewerId.isBlank();
    }

    /**
     * @param type    게시글 type. official(notice/event/patch) 은 사용자 수정·삭제·신고·차단 전부 불가.
     * @param status  "ACTIVE"/"HIDDEN" — 노출 게시글은 ACTIVE.
     * @param deleted soft-delete 여부.
     */
    public static PostFlags forPost(String viewerId, String authorId,
                                    String type, String status, boolean deleted, boolean authorIsAdmin) {
        boolean in = loggedIn(viewerId);
        boolean mine = in && viewerId.equals(authorId);          // ★순수 소유
        boolean official = BoardTaxonomy.isAdminType(type);
        boolean active = "ACTIVE".equals(status) && !deleted;
        boolean canEdit = mine && !official && active;           // 공식글=앱 수정/삭제 금지(관리자 웹 전용)
        boolean canReport = in && !mine;                         // ★1.0.4: 공식글 포함 비본인 글 신고 가능
        // ★canBlock 은 공통 판정 하나만(공식글 타입 OR 운영팀 작성자=자유글 포함 → 차단 금지). placeholder/override 없음.
        boolean canBlock = canBlockPostAuthor(viewerId, authorId, type, authorIsAdmin);
        return new PostFlags(mine, canEdit, canEdit, canReport, canBlock);
    }

    /**
     * @param parentCommentId  최상위면 null, 대댓글이면 부모(=최상위) commentId.
     * @param deleted          삭제 placeholder 면 작성자 정보·모든 액션 차단.
     * @param parentTopDeleted 최상위 부모가 삭제(placeholder)된 경우 — 답글 금지(서버 createComment 도 거부).
     * @param commentIsAdmin   댓글 작성자 운영팀 여부(저장값 is_admin).
     * @param authorIsAdmin    댓글 작성자 운영팀 여부(allowlist). 둘 중 하나라도 true 면 차단 금지(공통 판정).
     */
    public static CommentFlags forComment(String viewerId, String authorId, String commentId,
                                          String parentCommentId, boolean deleted,
                                          boolean parentTopDeleted, boolean commentIsAdmin, boolean authorIsAdmin) {
        if (deleted) {
            return new CommentFlags(false, false, false, null, false, false);
        }
        boolean in = loggedIn(viewerId);
        boolean mine = in && viewerId.equals(authorId);
        // 대댓글도 답글 버튼 노출하되 대상은 항상 최상위 댓글(2단 이상 금지). 최상위 부모 삭제 시 답글 불가.
        // ★1.0.4: 공식글에도 댓글 답글·신고·차단 허용(부모글 타입 무관). 차단 가능 여부는 ★댓글 작성자 운영팀 여부로만 판정.
        boolean canReply = in && !parentTopDeleted;
        String replyTarget = parentTopDeleted ? null : (parentCommentId != null ? parentCommentId : commentId);
        boolean canReport = in && !mine;            // ★운영자 댓글이어도 면제 없음
        // ★canBlock 은 공통 판정 하나만(운영팀 댓글이면 금지). placeholder/override 없음 — 이 메서드가 단일 source.
        boolean canBlock = canBlockCommentAuthor(viewerId, authorId, commentIsAdmin, authorIsAdmin);
        return new CommentFlags(mine, mine, canReply, replyTarget, canReport, canBlock);
    }

    // ─────────────────────────────────────────────────────────────────────
    // ★★공통 차단 가능 판정 — 자동차단(신고)·수동차단(BlockController)·UI canBlock(DTO) 가 모두 이 로직 하나만 사용.
    //   "운영팀(공식글 타입 또는 운영팀 작성자) 은 절대 차단 불가" 정책을 한 곳에서 보장.
    // ─────────────────────────────────────────────────────────────────────

    /** 게시글 작성자 차단 가능 여부. 금지: 미로그인 / 본인 / 공식글 타입(notice·event·patch) / 운영팀 작성자(자유글 포함). */
    public static boolean canBlockPostAuthor(String viewerId, String authorId, String type, boolean authorIsAdmin) {
        return loggedIn(viewerId) && !viewerId.equals(authorId)
                && !BoardTaxonomy.isAdminType(type) && !authorIsAdmin;
    }

    /** 댓글 작성자 차단 가능 여부. 금지: 미로그인 / 본인 / 운영팀이 쓴 댓글(부모글 타입 무관).
     *  일반 사용자가 공식글에 쓴 댓글은 차단 가능. commentIsAdmin(저장값) 또는 authorIsAdmin(allowlist) 중 하나라도 운영팀이면 금지. */
    public static boolean canBlockCommentAuthor(String viewerId, String authorId, boolean commentIsAdmin, boolean authorIsAdmin) {
        return loggedIn(viewerId) && !viewerId.equals(authorId)
                && !commentIsAdmin && !authorIsAdmin;
    }
}
