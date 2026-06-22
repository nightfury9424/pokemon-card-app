package com.fury.back.domain.board;

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
    private static final String ADMIN_AUTHOR = "운영팀";
    private static final String UNKNOWN_AUTHOR = "알 수 없음";
    private static final String DELETED_AUTHOR = "(삭제됨)";
    private static final String DELETED_BODY = "삭제된 댓글입니다";

    private final BoardPostRepository postRepository;
    private final BoardCommentRepository commentRepository;
    private final BlockRepository blockRepository;
    private final UserRepository userRepository;

    @Transactional(readOnly = true)
    public BoardPageDto getFeed(String section, String type, String viewerId, int page, int size) {
        if (section != null && !BoardTaxonomy.isValidSection(section)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "잘못된 섹션입니다.");
        }
        if (type != null && !BoardTaxonomy.isValidType(type)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "잘못된 타입입니다.");
        }
        if (section != null && type != null && !BoardTaxonomy.typeBelongsToSection(type, section)) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "섹션과 타입이 일치하지 않습니다.");
        }

        int p = Math.max(page, 0);
        int s = size <= 0 ? DEFAULT_SIZE : Math.min(size, MAX_SIZE);
        Page<BoardPost> posts = postRepository.findFeed(section, type, viewerId, PageRequest.of(p, s));
        List<BoardPost> list = posts.getContent();

        Map<String, String> nicknames = nicknameMap(
                list.stream().map(BoardPost::getAuthorId).collect(Collectors.toSet()));
        Map<String, Long> counts = commentCountMap(
                list.stream().map(BoardPost::getPostId).collect(Collectors.toList()));

        List<BoardPostSummaryDto> content = list.stream()
                .map(post -> toSummary(post, nicknames,
                        counts.getOrDefault(post.getPostId(), 0L).intValue()))
                .collect(Collectors.toList());

        return new BoardPageDto(content, posts.getNumber(), posts.getSize(),
                posts.getTotalElements(), posts.getTotalPages());
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

        List<BoardComment> all = commentRepository.findByPostIdOrderByCreatedAtAsc(postId);
        Set<String> authorIds = new HashSet<>();
        authorIds.add(post.getAuthorId());
        all.stream().filter(c -> !c.isDeleted()).forEach(c -> authorIds.add(c.getAuthorId()));
        Map<String, String> nicknames = nicknameMap(authorIds);

        List<BoardCommentDto> comments = assembleComments(all, nicknames);
        int activeCount = (int) all.stream().filter(c -> !c.isDeleted()).count();

        return new BoardPostDetailDto(
                post.getPostId(), post.getType(), post.getTitle(), post.getContent(),
                authorLabel(post.getType(), post.getAuthorId(), nicknames),
                post.getCreatedAt(), post.getViewCount(), post.getLikeCount(),
                post.isPinned(), post.isAnswered(), activeCount, comments);
    }

    // ── helpers ──

    private BoardPostSummaryDto toSummary(BoardPost p, Map<String, String> nick, int commentCount) {
        return new BoardPostSummaryDto(
                p.getPostId(), p.getType(), p.getTitle(), p.getContent(),
                authorLabel(p.getType(), p.getAuthorId(), nick),
                p.getCreatedAt(), p.getViewCount(), p.getLikeCount(),
                p.isPinned(), p.isAnswered(), commentCount);
    }

    /**
     * 1단 트리 조립. 삭제 규칙:
     *  - 최상위 삭제 + 답글 있음 → placeholder 노드 + 살아있는 답글
     *  - 최상위 삭제 + 답글 없음 → 제외
     *  - 답글 삭제 → 제외
     */
    private List<BoardCommentDto> assembleComments(List<BoardComment> all, Map<String, String> nick) {
        Map<String, List<BoardComment>> repliesByParent = all.stream()
                .filter(c -> !c.isTopLevel())
                .collect(Collectors.groupingBy(BoardComment::getParentCommentId,
                        LinkedHashMap::new, Collectors.toList()));

        List<BoardCommentDto> result = new ArrayList<>();
        for (BoardComment top : all) {
            if (!top.isTopLevel()) continue;
            List<BoardCommentDto> replies = repliesByParent
                    .getOrDefault(top.getCommentId(), List.of()).stream()
                    .filter(r -> !r.isDeleted())
                    .map(r -> toCommentDto(r, nick))
                    .collect(Collectors.toList());
            if (top.isDeleted()) {
                if (replies.isEmpty()) continue;
                result.add(placeholder(top, replies));
            } else {
                result.add(toCommentDto(top, nick, replies));
            }
        }
        return result;
    }

    private BoardCommentDto toCommentDto(BoardComment c, Map<String, String> nick) {
        return toCommentDto(c, nick, List.of());
    }

    private BoardCommentDto toCommentDto(BoardComment c, Map<String, String> nick, List<BoardCommentDto> replies) {
        String author = c.isAdmin() ? ADMIN_AUTHOR : nick.getOrDefault(c.getAuthorId(), UNKNOWN_AUTHOR);
        return new BoardCommentDto(c.getCommentId(), author, c.getContent(),
                c.getCreatedAt(), c.isAdmin(), c.isAccepted(), replies);
    }

    private BoardCommentDto placeholder(BoardComment c, List<BoardCommentDto> replies) {
        return new BoardCommentDto(c.getCommentId(), DELETED_AUTHOR, DELETED_BODY,
                c.getCreatedAt(), false, false, replies);
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
