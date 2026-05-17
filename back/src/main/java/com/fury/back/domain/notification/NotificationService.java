package com.fury.back.domain.notification;

import com.fury.back.common.IdGenerator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class NotificationService {

    private final NotificationRepository notificationRepository;

    @Value("${app.ops.admin-user-id:}")
    private String adminUserId;

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
        }
    }
}
