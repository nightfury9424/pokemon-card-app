package com.fury.back.domain.board;

import com.fury.back.domain.board.dto.BoardViewResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * 게시글 조회수 — 계정별 게시글당 최초 1회만 +1 (멱등). GET 상세가 아니라 별도 POST /view 로만 호출.
 * 중복/동시요청은 (post_id, viewer_id) UNIQUE 가 최종 기준. 작성자 본인·숨김/삭제 글은 미집계.
 */
@Service
@RequiredArgsConstructor
public class BoardViewService {

    private final BoardPostRepository postRepository;
    private final BoardPostViewRepository viewRepository;

    @Transactional
    public BoardViewResponse recordView(String viewerId, String postId) {
        // 비로그인(viewerId null)은 컨트롤러에서 미집계 처리.
        BoardPost post = postRepository.findById(postId).orElse(null);
        if (post == null || post.getDeletedAt() != null || !"ACTIVE".equals(post.getStatus())) {
            return new BoardViewResponse(false, post == null ? 0 : post.getViewCount());
        }
        if (viewerId == null || post.getAuthorId().equals(viewerId)) {
            return new BoardViewResponse(false, post.getViewCount()); // 작성자 본인·비로그인 제외
        }
        int inserted = viewRepository.insertIgnore(postId, viewerId);
        if (inserted == 1) {
            postRepository.incrementViewCount(postId);
            return new BoardViewResponse(true, post.getViewCount() + 1); // DB +1 확정값
        }
        return new BoardViewResponse(false, post.getViewCount()); // 이미 조회한 계정
    }
}
