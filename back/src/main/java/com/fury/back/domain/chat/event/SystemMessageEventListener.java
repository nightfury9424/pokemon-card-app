package com.fury.back.domain.chat.event;

import com.fury.back.domain.chat.dto.ChatMessageDto;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.event.TransactionPhase;
import org.springframework.transaction.event.TransactionalEventListener;

/**
 * Bundle 2-C — 시스템 메시지를 commit 확정 후 STOMP broadcast.
 *
 * <p>{@code AFTER_COMMIT}: chat_messages INSERT가 실제 DB에 반영된 후에만 broadcast.
 * commit 실패 시 메시지만 먼저 퍼지는 race 차단 (Codex 사전검토 agentId a32790e3 권장).
 *
 * <p>일반 메시지({@code /topic/room/{roomId}})와 같은 topic — 클라이언트가
 * {@code messageType='SYSTEM'} 분기로 가운데 회색 텍스트 렌더링.
 */
@Component
@RequiredArgsConstructor
public class SystemMessageEventListener {

    private final SimpMessagingTemplate messagingTemplate;

    @TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
    public void onSystemMessage(SystemMessageEvent event) {
        // ChatMessageDto는 명시적 type — convertAndSend(D, Object) ↔ headers map 시그니처 ambiguity 없음.
        final ChatMessageDto payload = event.message();
        messagingTemplate.convertAndSend("/topic/room/" + event.roomId(), payload);
    }
}
