package com.fury.back.domain.board;

import com.fury.back.auth.AdminAuthorizationService;
import com.fury.back.domain.block.BlockRepository;
import com.fury.back.domain.board.dto.*;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.util.*;
import java.util.stream.Collectors;

/**
 * 게시판 읽기 서비스 (Slice 1A). 목록/상세 조회만.
 * 404/400 = ResponseStatusException(GlobalExceptionHandler 가 실제 status 보존).
 */
@Service
@RequiredArgsConstructor
public class BoardService {

    private static final int DEFAULT_SIZE = 20;
    private static final int MAX_SIZE = 50;
    private static final int MAX_QUERY_LEN = 50; // 제목 검색어 최대 길이
    private static final String ADMIN_AUTHOR = "운영팀";
    private static final String UNKNOWN_AUTHOR = "알 수 없음";
    private static final String DELETED_AUTHOR = "(삭제됨)";
    private static final String DELETED_BODY = "삭제된 댓글입니다";

    private final BoardPostRepository postRepository;
    private final BoardCommentRepository commentRepository;
    private final BlockRepository blockRepository;
    private final UserRepository userRepository;
    private final BoardPostLikeRepository likeRepository;
    private final BoardPostImageRepository postImageRepository;
    private final AdminAuthorizationService adminAuth; // 작성자 운영팀 여부(공통 차단 판정)

    @Transactional(readOnly = true)
    public BoardPageDto getFeed(String section, String type, String q, boolean pinnedOnly,
                                String viewerId, int page, int size) {
        if (section != null && !BoardTaxonomy.isValidSection(section)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "잘못된 섹션입니다.");
        }
        if (type != null && !BoardTaxonomy.isValidType(type)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "잘못된 타입입니다.");
        }
        if (section != null && type != null && !BoardTaxonomy.typeBelongsToSection(type, section)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "섹션과 타입이 일치하지 않습니다.");
        }

        if (page < 0) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "page 는 0 이상이어야 합니다.");
        }
        int s = size <= 0 ? DEFAULT_SIZE : Math.min(size, MAX_SIZE);
        // ★제목 검색어: trim + 빈 문자열=null(미적용) + 최대 길이 클램프. 본문/작성자 미검색(repo가 title만 LIKE).
        String nq = (q == null || q.isBlank()) ? null : q.trim();
        if (nq != null && nq.length() > MAX_QUERY_LEN) nq = nq.substring(0, MAX_QUERY_LEN);
        // ★PG가 null 파라미터를 bytea 로 추론(lower(bytea) 오류) → %·LOWER 를 Java 에서 조립해 LIKE 직접 전달.
        String qLike = (nq == null) ? null : "%" + nq.toLowerCase() + "%";
        Page<BoardPost> posts = postRepository.findFeed(section, type, qLike, pinnedOnly, viewerId, PageRequest.of(page, s));
        List<BoardPost> list = posts.getContent();

        List<String> postIds = list.stream().map(BoardPost::getPostId).collect(Collectors.toList());
        Map<String, String> nicknames = nicknameMap(
                list.stream().map(BoardPost::getAuthorId).collect(Collectors.toSet()));
        Map<String, Long> counts = commentCountMap(postIds);
        Map<String, Integer> likeCounts = likeCountMap(postIds);  // bulk 1쿼리
        Set<String> liked = likedPostIds(viewerId, postIds);      // bulk 1쿼리(viewer 있을 때만)
        Map<String, ImageSummary> images = imageSummaryMap(postIds); // bulk 1쿼리(N+1 금지)

        List<BoardPostSummaryDto> content = list.stream()
                .map(post -> {
                    ImageSummary is = images.get(post.getPostId());
                    String thumbUrl = (is != null && is.thumbnailKey() != null)
                            ? com.fury.back.storage.StorageKeyUrls.toProxyUrl(is.thumbnailKey())
                            : null; // raw 키 미노출
                    int imgCount = is != null ? is.count() : 0;
                    return toSummary(post, nicknames,
                            counts.getOrDefault(post.getPostId(), 0L).intValue(), viewerId,
                            likeCounts.getOrDefault(post.getPostId(), 0),
                            liked.contains(post.getPostId()), thumbUrl, imgCount);
                })
                .collect(Collectors.toList());

        return new BoardPageDto(content, posts.getNumber(), posts.getSize(),
                posts.getTotalElements(), posts.getTotalPages());
    }

    /** 검색·핀필터 없는 5-arg 오버로드(q=null, pinnedOnly=false) — 기존 호출 호환. */
    @Transactional(readOnly = true)
    public BoardPageDto getFeed(String section, String type, String viewerId, int page, int size) {
        return getFeed(section, type, null, false, viewerId, page, size);
    }

    @Transactional(readOnly = true)
    public BoardPostDetailDto getDetail(String postId, String viewerId) {
        BoardPost post = postRepository.findById(postId)
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        // 차단 author 글 → 뷰어에게 존재 비노출(404)
        if (viewerId != null && blockRepository.existsByBlockerIdAndBlockedId(viewerId, post.getAuthorId())) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다.");
        }

        // 차단 author 댓글·대댓글 → 뷰어에게 제외(글 필터와 동일 단방향 blocker→blocked).
        final Set<String> blockedAuthors = (viewerId == null)
                ? Collections.emptySet()
                : blockRepository.findAllByBlockerId(viewerId).stream()
                        .map(b -> b.getBlockedId()).collect(Collectors.toSet());
        List<BoardComment> raw = commentRepository.findByPostIdOrderByCreatedAtAsc(postId);
        // 차단 author 댓글 제거 + 차단으로 사라진 최상위에 달렸던 답글(부모 상실)도 제거 → 노출=집계 일치.
        Set<String> keptTopIds = raw.stream()
                .filter(c -> c.isTopLevel() && !blockedAuthors.contains(c.getAuthorId()))
                .map(BoardComment::getCommentId).collect(Collectors.toSet());
        List<BoardComment> all = raw.stream()
                .filter(c -> !blockedAuthors.contains(c.getAuthorId()))
                .filter(c -> c.isTopLevel() || keptTopIds.contains(c.getParentCommentId()))
                .collect(Collectors.toList());
        Set<String> authorIds = new HashSet<>();
        authorIds.add(post.getAuthorId());
        all.stream().filter(c -> !c.isDeleted()).forEach(c -> authorIds.add(c.getAuthorId()));
        Map<String, String> nicknames = nicknameMap(authorIds);

        boolean community = !BoardTaxonomy.isAdminType(post.getType());
        List<BoardCommentDto> comments = assembleComments(all, nicknames, viewerId, community);
        int activeCount = (int) all.stream().filter(c -> !c.isDeleted()).count();

        BoardPermissions.PostFlags pf = BoardPermissions.forPost(
                viewerId, post.getAuthorId(), post.getType(), post.getStatus(), post.getDeletedAt() != null,
                adminAuth.isAdmin(post.getAuthorId()));
        List<String> ids = List.of(post.getPostId());
        int likeCount = likeCountMap(ids).getOrDefault(post.getPostId(), 0);   // board_post_likes COUNT(*)
        boolean likedByMe = likedPostIds(viewerId, ids).contains(post.getPostId());
        List<com.fury.back.domain.board.dto.BoardPostImageDto> images =
                postImageRepository.findByPostIdOrderBySortOrderAsc(post.getPostId()).stream()
                        .map(img -> new com.fury.back.domain.board.dto.BoardPostImageDto(
                                img.getImageId(),
                                com.fury.back.storage.StorageKeyUrls.toProxyUrl(img.getStorageKey()), // raw 키 미노출
                                img.getSortOrder()))
                        .toList();
        return new BoardPostDetailDto(
                post.getPostId(), post.getType(), post.getTitle(), post.getContent(),
                authorLabel(post.getType(), post.getAuthorId(), nicknames),
                post.getCreatedAt(), post.getViewCount(), likeCount,
                post.isPinned(), post.isAnswered(), activeCount, comments,
                pf.mine(), pf.canEdit(), pf.canDelete(), pf.canReport(), pf.canBlock(),
                likedByMe, images);
    }

    // ── helpers ──

    private BoardPostSummaryDto toSummary(BoardPost p, Map<String, String> nick, int commentCount,
                                          String viewerId, int likeCount, boolean likedByMe,
                                          String thumbnailUrl, int imageCount) {
        BoardPermissions.PostFlags pf = BoardPermissions.forPost(
                viewerId, p.getAuthorId(), p.getType(), p.getStatus(), p.getDeletedAt() != null,
                adminAuth.isAdmin(p.getAuthorId()));
        return new BoardPostSummaryDto(
                p.getPostId(), p.getType(), p.getTitle(), p.getContent(),
                authorLabel(p.getType(), p.getAuthorId(), nick),
                p.getCreatedAt(), p.getViewCount(), likeCount,
                p.isPinned(), p.isAnswered(), commentCount,
                pf.mine(), pf.canEdit(), pf.canDelete(), pf.canReport(), pf.canBlock(),
                likedByMe, thumbnailUrl, imageCount);
    }

    /** 페이지 postId 들의 첫 이미지(sort 0)·총개수 bulk 조회(N+1 금지). 첫 이미지 = sort_order 최소. */
    private Map<String, ImageSummary> imageSummaryMap(List<String> postIds) {
        if (postIds.isEmpty()) {
            return Map.of();
        }
        Map<String, Integer> counts = new HashMap<>();
        Map<String, String> firstKey = new HashMap<>();
        // sort_order ASC 정렬 → 전 행이 sort 오름차순이라 postId 별 첫 등장 = sort 최소(=썸네일).
        for (BoardPostImage img : postImageRepository.findByPostIdInOrderBySortOrderAsc(postIds)) {
            counts.merge(img.getPostId(), 1, Integer::sum);
            firstKey.putIfAbsent(img.getPostId(), img.getStorageKey());
        }
        Map<String, ImageSummary> m = new HashMap<>();
        for (Map.Entry<String, Integer> e : counts.entrySet()) {
            m.put(e.getKey(), new ImageSummary(firstKey.get(e.getKey()), e.getValue()));
        }
        return m;
    }

    private record ImageSummary(String thumbnailKey, int count) {}

    /** 게시글별 좋아요 수 batch(board_post_likes COUNT). 빈 목록이면 호출 생략. */
    private Map<String, Integer> likeCountMap(List<String> postIds) {
        if (postIds.isEmpty()) return Map.of();
        Map<String, Integer> m = new HashMap<>();
        for (Object[] r : likeRepository.countByPostIdIn(postIds)) {
            m.put((String) r[0], ((Number) r[1]).intValue());
        }
        return m;
    }

    /** viewer 가 좋아요한 postId 집합(비로그인/빈 목록 → 빈 집합, 쿼리 생략). */
    private Set<String> likedPostIds(String viewerId, List<String> postIds) {
        if (viewerId == null || postIds.isEmpty()) return Set.of();
        return new HashSet<>(likeRepository.findLikedPostIds(viewerId, postIds));
    }

    /**
     * 1단 트리 조립. 삭제 규칙:
     *  - 최상위 삭제 + 답글 있음 → placeholder 노드 + 살아있는 답글
     *  - 최상위 삭제 + 답글 없음 → 제외
     *  - 답글 삭제 → 제외
     */
    private List<BoardCommentDto> assembleComments(
            List<BoardComment> all, Map<String, String> nick, String viewerId, boolean community) {
        Map<String, List<BoardComment>> repliesByParent = all.stream()
                .filter(c -> !c.isTopLevel())
                .collect(Collectors.groupingBy(BoardComment::getParentCommentId,
                        LinkedHashMap::new, Collectors.toList()));

        List<BoardCommentDto> result = new ArrayList<>();
        for (BoardComment top : all) {
            if (!top.isTopLevel()) continue;
            boolean topDeleted = top.isDeleted();
            List<BoardCommentDto> replies = repliesByParent
                    .getOrDefault(top.getCommentId(), List.of()).stream()
                    .filter(r -> !r.isDeleted())
                    // ★최상위 부모 삭제 여부 전달 — 삭제된 top 아래 답글은 canReply=false
                    .map(r -> toCommentDto(r, nick, viewerId, community, topDeleted))
                    .collect(Collectors.toList());
            if (topDeleted) {
                if (replies.isEmpty()) continue;
                result.add(placeholder(top, replies));
            } else {
                result.add(toCommentDto(top, nick, replies, viewerId, community, false));
            }
        }
        return result;
    }

    private BoardCommentDto toCommentDto(BoardComment c, Map<String, String> nick,
                                         String viewerId, boolean community, boolean parentTopDeleted) {
        return toCommentDto(c, nick, List.of(), viewerId, community, parentTopDeleted);
    }

    private BoardCommentDto toCommentDto(BoardComment c, Map<String, String> nick, List<BoardCommentDto> replies,
                                         String viewerId, boolean community, boolean parentTopDeleted) {
        String author = c.isAdmin() ? ADMIN_AUTHOR : nick.getOrDefault(c.getAuthorId(), UNKNOWN_AUTHOR);
        BoardPermissions.CommentFlags f = BoardPermissions.forComment(
                viewerId, c.getAuthorId(), c.getCommentId(), c.getParentCommentId(), false,
                parentTopDeleted, c.isAdmin(), adminAuth.isAdmin(c.getAuthorId()));
        return new BoardCommentDto(c.getCommentId(), author, c.getContent(),
                c.getCreatedAt(), c.isAdmin(), c.isAccepted(), replies,
                f.mine(), f.canDelete(), f.canReply(), f.replyTargetCommentId(), f.canReport(), f.canBlock());
    }

    private BoardCommentDto placeholder(BoardComment c, List<BoardCommentDto> replies) {
        // 삭제 댓글: 작성자 정보·모든 액션 차단(forComment deleted=true 와 동일).
        return new BoardCommentDto(c.getCommentId(), DELETED_AUTHOR, DELETED_BODY,
                c.getCreatedAt(), false, false, replies,
                false, false, false, null, false, false);
    }

    private String authorLabel(String type, String authorId, Map<String, String> nick) {
        if (BoardTaxonomy.isAdminType(type)) return ADMIN_AUTHOR;
        return nick.getOrDefault(authorId, UNKNOWN_AUTHOR);
    }

    private Map<String, String> nicknameMap(Set<String> ids) {
        if (ids.isEmpty()) return Map.of();
        Map<String, String> m = new HashMap<>();
        for (User u : userRepository.findAllById(ids)) {
            m.put(u.getUserId(), u.getNickname() != null ? u.getNickname() : UNKNOWN_AUTHOR);
        }
        return m;
    }

    private Map<String, Long> commentCountMap(List<String> postIds) {
        if (postIds.isEmpty()) return Map.of();
        Map<String, Long> m = new HashMap<>();
        for (BoardCommentRepository.PostCommentCount r : commentRepository.countActiveByPostIds(postIds)) {
            m.put(r.getPostId(), r.getCnt());
        }
        return m;
    }
}
