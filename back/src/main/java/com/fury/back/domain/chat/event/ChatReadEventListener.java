package com.fury.back.domain.chat.event;

import lombok.RequiredArgsConstructor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

import java.util.Map;

/**
 * Bundle 1 G1 — read 이벤트를 commit 확정 후 STOMP broadcast.
 *
 * <p>{@code AFTER_COMMIT}: read UPDATE가 실제로 DB에 반영된 후에만 broadcast.
 * commit 실패 시 read 이벤트만 먼저 퍼지는 위험 차단 (Codex 사전검토 권장 a2cef087).
 *
 * <p>topic: {@code /topic/room/{roomId}/read}
 * <br>payload: {@code { roomId, readerUserId }}
 */
@Component
@RequiredArgsConstructor
public class ChatReadEventListener {

    private final SimpMessagingTemplate messagingTemplate;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onRead(ChatReadEvent event) {
        // payload type Object 명시 — convertAndSend(D, Object) ↔ (Object, Map<String,Object> headers) 시그니처 ambiguity 회피.
        final Object payload = Map.of(
                "roomId", event.roomId(),
                "readerUserId", event.readerUserId()
        );
        messagingTemplate.convertAndSend(
                "/topic/room/" + event.roomId() + "/read",
                payload
        );
    }
}
