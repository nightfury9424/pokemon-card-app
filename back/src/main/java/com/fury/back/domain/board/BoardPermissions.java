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
                                    String type, String status, boolean deleted) {
        boolean in = loggedIn(viewerId);
        boolean mine = in && viewerId.equals(authorId);          // ★순수 소유
        boolean official = BoardTaxonomy.isAdminType(type);
        boolean active = "ACTIVE".equals(status) && !deleted;
        boolean canEdit = mine && !official && active;           // 공식글=앱 수정/삭제 금지(관리자 웹 전용)
        boolean canReport = in && !mine;                         // ★1.0.4: 공식글 포함 비본인 글 신고 가능
        boolean canBlock = in && !mine && !official;             // 공식(운영팀) 차단 불가, 그 외 비본인 차단
        return new PostFlags(mine, canEdit, canEdit, canReport, canBlock);
    }

    /**
     * @param parentCommentId 최상위면 null, 대댓글이면 부모(=최상위) commentId.
     * @param deleted         삭제 placeholder 면 작성자 정보·모든 액션 차단.
     * @param community       게시글이 community(자유 등)인지. 공식글엔 댓글이 없어야 하나 방어적으로 게이트.
     */
    public static CommentFlags forComment(String viewerId, String authorId, String commentId,
                                          String parentCommentId, boolean deleted, boolean community) {
        return forComment(viewerId, authorId, commentId, parentCommentId, deleted, community, false);
    }

    /**
     * @param parentTopDeleted 이 댓글이 달린 최상위 부모가 삭제(placeholder)된 경우 — 답글 금지
     *                         (서버 createComment 도 삭제된 부모엔 거부 → UI 플래그와 일치).
     */
    public static CommentFlags forComment(String viewerId, String authorId, String commentId,
                                          String parentCommentId, boolean deleted, boolean community,
                                          boolean parentTopDeleted) {
        if (deleted) {
            return new CommentFlags(false, false, false, null, false, false);
        }
        boolean in = loggedIn(viewerId);
        boolean mine = in && viewerId.equals(authorId);
        // 대댓글에도 답글 버튼 노출하되 대상은 항상 최상위 댓글(2단 이상 금지). 서버가 createComment 에서 재검증.
        // ★최상위 부모가 삭제된 경우엔 답글 불가(서버도 거부) → canReply=false, target=null.
        // ★1.0.4: 공식글(community=false)에도 댓글 답글·신고·차단 허용 → community 게이트 제거.
        //   (공식 '게시글' 자체의 수정/삭제는 forPost 에서 계속 관리자 전용으로 유지)
        boolean canReply = in && !parentTopDeleted;
        String replyTarget = parentTopDeleted ? null : (parentCommentId != null ? parentCommentId : commentId);
        boolean canReport = in && !mine;            // ★운영자 댓글이어도 면제 없음
        boolean canBlock = in && !mine;
        return new CommentFlags(mine, mine, canReply, replyTarget, canReport, canBlock);
    }
}
