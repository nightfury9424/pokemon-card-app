package com.fury.back.domain.board.event;

import com.fury.back.domain.notification.NotificationService;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * 게시판 알림 — 좋아요/댓글/대댓글 본 작업이 DB commit 된 뒤(AFTER_COMMIT) 알림 row + 푸시.
 * FCM 오류는 본 작업을 롤백시키지 않는다(별 트랜잭션). self·차단·중복(dedup_key) 제외는 NotificationService 가 처리.
 */
@Component
@RequiredArgsConstructor
public class BoardNotificationEventListener {

    private final NotificationService notificationService;
    private final UserRepository userRepository;

    private String nick(String userId) {
        return userRepository.findById(userId)
                .map(u -> u.getNickname())
                .filter(n -> n != null && !n.isBlank())
                .orElse("사용자");
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onLike(BoardPostLikedEvent e) {
        notificationService.notifyBoardPostLike(e.postAuthorId(), e.actorId(), nick(e.actorId()), e.postId());
    }

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onComment(BoardCommentCreatedEvent e) {
        String nick = nick(e.actorId());
        if (e.parentCommentId() == null) {
            // 최상위 댓글 → 게시글 작성자에게 알림
            notificationService.notifyBoardPostComment(
                    e.postAuthorId(), e.actorId(), nick, e.postId(), e.commentId());
        } else {
            // 대댓글 → 부모 댓글 작성자=답글 알림. 게시글 작성자가 다르면 댓글 활동 알림도(같으면 답글 1개만).
            notificationService.notifyBoardCommentReply(
                    e.parentAuthorId(), e.actorId(), nick, e.postId(), e.commentId());
            if (e.postAuthorId() != null && !e.postAuthorId().equals(e.parentAuthorId())) {
                notificationService.notifyBoardPostComment(
                        e.postAuthorId(), e.actorId(), nick, e.postId(), e.commentId());
            }
        }
    }
}
