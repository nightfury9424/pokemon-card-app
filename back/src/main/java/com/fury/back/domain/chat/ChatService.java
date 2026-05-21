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
}
