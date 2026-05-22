package com.fury.back.domain.chat;

import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;

import java.util.List;

public interface ChatService {
    ChatRoomDto getOrCreateRoom(String saleListingId, String buyerUserId);
    List<ChatRoomDto> getMyRooms(String userId);
    List<ChatMessageDto> getMessages(String roomId, String userId);
    ChatMessageDto sendMessage(String roomId, String senderUserId, String message);

    /**
     * Bundle 1.5 (active read gap): 채팅방에 active 상태로 있을 때 새 메시지 도착 시
     * 즉시 read 처리용 lightweight endpoint. 메시지 리스트 반환 X.
     */
    void markRoomAsRead(String roomId, String userId);

    /**
     * Bundle 2-C: 시스템 메시지 전송 (sender_user_id='SYSTEM', message_type='SYSTEM').
     * 상태 변경/사기 주의 안내 등 자동 메시지에 사용.
     * AFTER_COMMIT 이벤트로 STOMP broadcast — 일반 메시지와 동일 topic에 push.
     */
    ChatMessageDto sendSystemMessage(String roomId, String content);

    /**
     * Bundle 2-D: trade 상태 변경 시 해당 trade의 모든 chat_room에 시스템 메시지 fan-out.
     * - 1 trade ↔ N buyer 패턴 (UNIQUE 정책상 same buyer 1방 보장, 다른 buyer 각각)
     * - sendSystemMessage 동일 인프라 활용 — AFTER_COMMIT broadcast
     */
    void broadcastTradeStatusChanged(String saleListingId, String newStatus);
}
