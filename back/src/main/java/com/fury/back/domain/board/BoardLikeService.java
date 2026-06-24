package com.fury.back.domain.board;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.board.dto.BoardLikeResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * 게시판 좋아요 쓰기 (멱등). board_post_likes 가 source of truth, likeCount = COUNT(*).
 *
 * <p>정책(1.0.4): type='free' 의 ACTIVE·미삭제 글만 좋아요 가능(공지/그 외 타입=403, 미존재/HIDDEN/삭제=404,
 * 비로그인=401, 본인 글 허용). 중복 PUT/DELETE 는 멱등(UNIQUE + ON CONFLICT / 0·1행 삭제).
 */
@Service
@RequiredArgsConstructor
public class BoardLikeService {

    private final BoardPostRepository postRepository;
    private final BoardPostLikeRepository likeRepository;

    /** 좋아요(멱등). 이미 눌렀어도 likedByMe=true. */
    @Transactional
    public BoardLikeResponse like(String userId, String postId) {
        requireLikeablePost(userId, postId);
        likeRepository.insertIgnore(IdGenerator.generate(), postId, userId); // 충돌 시 no-op
        return new BoardLikeResponse(true, likeRepository.countByPostId(postId));
    }

    /** 좋아요 취소(멱등). 안 눌렀어도 likedByMe=false. */
    @Transactional
    public BoardLikeResponse unlike(String userId, String postId) {
        requireLikeablePost(userId, postId);
        likeRepository.deleteByPostIdAndUserId(postId, userId); // 0/1행
        return new BoardLikeResponse(false, likeRepository.countByPostId(postId));
    }

    /** 좋아요 가능 게시글 검증. 비로그인=401, 미존재/HIDDEN/삭제=404, free 외=403. */
    private void requireLikeablePost(String userId, String postId) {
        if (userId == null) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "로그인이 필요합니다.");
        }
        BoardPost post = postRepository.findById(postId)
                .filter(p -> p.getDeletedAt() == null && "ACTIVE".equals(p.getStatus()))
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "게시글을 찾을 수 없습니다."));
        // ★1.0.4: 노출 타입(notice/event/patch/free)에 좋아요 허용 — 공지계열 포함. qna/그 외=거부.
        if (!BoardTaxonomy.isBoardVisibleType(post.getType())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "좋아요할 수 없는 게시글입니다.");
        }
    }
}
