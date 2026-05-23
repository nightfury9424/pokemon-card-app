package com.fury.back.domain.chat;

import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;
import com.fury.back.domain.chat.dto.ConversationStateDto;

import java.util.List;

public interface ChatService {
    ChatRoomDto getOrCreateRoom(String saleListingId, String buyerUserId);
    List<ChatRoomDto> getMyRooms(String userId);
    List<ChatMessageDto> getMessages(String roomId, String userId);
    ChatMessageDto sendMessage(String roomId, String senderUserId, String message);

    /**
     * Phase 1: 채팅방 나가기 — 본인의 hidden_at set. DB 보존, 본인 목록에서만 숨김.
     * 참여자 검증 후 buyer/seller 분기 자동.
     */
    void leaveRoom(String roomId, String userId);

    /**
     * Phase 1: 채팅방 진입 시 입력창/안내 상태 조회.
     * 차단 관계가 있으면 canSendMessage=false + blockNotice 문구 반환.
     */
    ConversationStateDto getConversationState(String roomId, String userId);

    /**
     * Phase 1: 차단 액션 hook — 두 사용자 사이 모든 방에 차단한 사람 hidden_at set
     * + 각 방에 "상대방의 설정으로 인해 더 이상 대화할 수 없습니다." SYSTEM 메시지 1회.
     * BlockController 가 차단 저장 후 호출.
     */
    void notifyBlock(String blockerId, String blockedId);

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
