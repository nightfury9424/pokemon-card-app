package com.fury.back.domain.notification;

import com.fury.back.common.IdGenerator;
import com.fury.back.domain.block.BlockRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class NotificationService {

    private final NotificationRepository notificationRepository;
    private final FcmService fcmService;
    private final BlockRepository blockRepository;

    @Value("${app.ops.admin-user-id:}")
    private String adminUserId;

    // ── 게시판 알림(좋아요/댓글/대댓글) — AFTER_COMMIT 리스너에서 호출. self·차단·중복(dedup_key) 제외. ──
    // ★REQUIRES_NEW = 본 작업(좋아요/댓글) commit 후 AFTER_COMMIT 리스너가 호출 → 별도 신규 트랜잭션으로
    //   알림 row 를 독립 commit(REQUIRED 면 완료중 tx 에 참여해 유실됨). FCM 실패는 createBoardNotification 가 흡수.

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void notifyBoardPostLike(String postAuthorId, String actorId, String actorNick, String postId) {
        createBoardNotification(postAuthorId, actorId, "BOARD_POST_LIKE",
                "내 게시글 좋아요",
                actorNick + "님이 회원님의 게시글을 좋아합니다.",
                "/board/" + postId,
                "BOARD_POST_LIKE:" + postId + ":" + actorId + ":" + postAuthorId);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void notifyBoardPostComment(String postAuthorId, String actorId, String actorNick,
            String postId, String commentId) {
        createBoardNotification(postAuthorId, actorId, "BOARD_POST_COMMENT",
                "내 게시글에 댓글",
                actorNick + "님이 회원님의 게시글에 댓글을 남겼습니다.",
                "/board/" + postId + "?comment=" + commentId,
                "BOARD_POST_COMMENT:" + commentId + ":" + postAuthorId);
    }

    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void notifyBoardCommentReply(String parentAuthorId, String actorId, String actorNick,
            String postId, String replyId) {
        createBoardNotification(parentAuthorId, actorId, "BOARD_COMMENT_REPLY",
                "내 댓글에 답글",
                actorNick + "님이 회원님의 댓글에 답글을 남겼습니다.",
                "/board/" + postId + "?comment=" + replyId,
                "BOARD_COMMENT_REPLY:" + replyId + ":" + parentAuthorId);
    }

    private void createBoardNotification(String recipientId, String actorId, String type,
            String title, String body, String linkUrl, String dedupKey) {
        if (recipientId == null || recipientId.equals(actorId)) return; // 자기 행동 제외
        // 차단 양방향 — 하나라도 있으면 알림 row·푸시 모두 생성 안 함
        if (blockRepository.existsByBlockerIdAndBlockedId(recipientId, actorId)
                || blockRepository.existsByBlockerIdAndBlockedId(actorId, recipientId)) return;
        int inserted = notificationRepository.insertIgnoreDedup(
                IdGenerator.generate(), recipientId, type, title, body, linkUrl, dedupKey);
        if (inserted == 1) { // 신규 알림일 때만 푸시(중복 dedup → no-op)
            try {
                fcmService.sendToUser(recipientId, title, body,
                        Map.of("type", type, "linkUrl", linkUrl == null ? "" : linkUrl));
            } catch (Exception e) {
                // ★FCM 발송 실패(FirebaseMessagingException 외 RuntimeException 포함)는 인앱 알림 row·본 작업을
                //   롤백시키지 않는다. notification row 는 이미 INSERT 되어 commit 되고, 푸시만 유실하며 로그만 남긴다.
                log.warn("[BOARD_NOTI] FCM 발송 실패 recipient={} type={} (알림 row·본 작업 유지, 푸시만 유실)",
                        recipientId, type, e);
            }
        }
    }

    public List<Notification> getRecent(String userId) {
        return notificationRepository.findTop50ByUserIdOrderByCreatedAtDesc(userId);
    }

    public long getUnreadCount(String userId) {
        return notificationRepository.countByUserIdAndIsReadFalse(userId);
    }

    @Transactional
    public void markRead(String notificationId, String userId) {
        notificationRepository.findById(notificationId).ifPresent(n -> {
            if (n.getUserId().equals(userId)) {
                n.markRead();
            }
        });
    }

    @Transactional
    public void markAllRead(String userId) {
        notificationRepository.findTop50ByUserIdOrderByCreatedAtDesc(userId)
                .forEach(n -> { if (!n.getIsRead()) n.markRead(); });
    }

    /**
     * 운영 잡 실패 알림 — PriceSyncScheduler 등 백그라운드 스크래퍼가 exit != 0 끝낼 때.
     * `app.ops.admin-user-id` 미설정이면 알림 생성 안 함 (log만).
     */
    @Transactional
    public void notifyOpsFailure(String scriptName, int exitCode, String summary) {
        if (adminUserId == null || adminUserId.isBlank()) {
            log.warn("[Ops] 알림 user_id 미설정 (app.ops.admin-user-id). 실패만 로그: {} exit={}", scriptName, exitCode);
            return;
        }
        String safeSummary = summary == null ? "" : summary;
        if (safeSummary.length() > 1500) safeSummary = safeSummary.substring(0, 1500);
        Notification n = Notification.builder()
                .notificationId(IdGenerator.generate())
                .userId(adminUserId)
                .type("OPS_PIPELINE_FAILURE")
                .title("시세 수집 실패: " + scriptName)
                .body("exit code " + exitCode + (safeSummary.isEmpty() ? "" : " — " + safeSummary))
                .isRead(false)
                .build();
        notificationRepository.save(n);
        fcmService.sendToUser(adminUserId, n.getTitle(), n.getBody(), Map.of("type", n.getType()));
        log.warn("[Ops] 알림 row 생성: {} exit={}", scriptName, exitCode);
    }

    /** 매수 호가 등록 시 — 같은 카드를 보유한 사용자들에게 알림. */
    @Transactional
    public void notifyBuyOrderToCardHolders(
            List<String> holderUserIds,
            String cardId,
            String cardName,
            int bidPrice,
            String buyerNickname) {
        for (String userId : holderUserIds) {
            Notification n = Notification.builder()
                    .notificationId(IdGenerator.generate())
                    .userId(userId)
                    .type("BUY_ORDER_ON_MY_CARD")
                    .title("내 카드에 매수 호가가 등록됐어요")
                    .body("$buyerNickname"
                            .replace("$buyerNickname", buyerNickname != null ? buyerNickname : "구매자")
                            + "님이 " + cardName + " 카드를 "
                            + java.text.NumberFormat.getInstance().format(bidPrice)
                            + "원에 사고 싶다고 등록했어요.")
                    .linkCardId(cardId)
                    .isRead(false)
                    .build();
            notificationRepository.save(n);
            fcmService.sendToUser(userId, n.getTitle(), n.getBody(),
                    Map.of("type", n.getType(), "cardId", cardId == null ? "" : cardId));
        }
    }

    /** 판매 호가 등록 시 — 같은 카드에 매수 호가 등록한 사용자들에게 알림. */
    @Transactional
    public void notifyTradePostToBuyers(
            List<String> buyerUserIds,
            String cardId,
            String cardName,
            int price,
            String sellerNickname) {
        for (String userId : buyerUserIds) {
            Notification n = Notification.builder()
                    .notificationId(IdGenerator.generate())
                    .userId(userId)
                    .type("TRADE_ON_MY_BUY_ORDER")
                    .title("매수 호가 카드가 판매 등록됐어요")
                    .body("$sellerNickname"
                            .replace("$sellerNickname", sellerNickname != null ? sellerNickname : "판매자")
                            + "님이 " + cardName + " 카드를 "
                            + java.text.NumberFormat.getInstance().format(price)
                            + "원에 등록했어요.")
                    .linkCardId(cardId)
                    .isRead(false)
                    .build();
            notificationRepository.save(n);
            fcmService.sendToUser(userId, n.getTitle(), n.getBody(),
                    Map.of("type", n.getType(), "cardId", cardId == null ? "" : cardId));
        }
    }

    /**
     * 고객 문의 답변 등록 시 — 문의한 사용자에게 인앱 알림 + FCM 푸시.
     * ★답변 내용을 body 에 담아 별도 화면 없이 벨에서 바로 확인 가능(앱 변경 불필요).
     * 호출측(InquiryAdminController.reply)이 try-catch 로 감싸 답변 등록은 절대 영향 없음.
     */
    @Transactional
    public void notifyInquiryAnswered(String userId, String inquiryTitle, String reply) {
        if (userId == null || userId.isBlank()) return;
        String r = reply == null ? "" : reply.trim();
        String snippet = r.length() > 300 ? r.substring(0, 300) + "…" : r;
        String prefix = (inquiryTitle != null && !inquiryTitle.isBlank()) ? "[" + inquiryTitle + "] " : "";
        Notification n = Notification.builder()
                .notificationId(IdGenerator.generate())
                .userId(userId)
                .type("INQUIRY_ANSWERED")
                .title("문의 답변이 등록됐어요")
                .body(prefix + snippet)
                .isRead(false)
                .build();
        notificationRepository.save(n);
        fcmService.sendToUser(userId, n.getTitle(), n.getBody(), Map.of("type", n.getType()));
    }
}
