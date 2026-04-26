package com.fury.back.domain.chat;

import com.fury.back.domain.chat.dto.ChatMessageDto;
import com.fury.back.domain.chat.dto.ChatRoomDto;

import java.util.List;

public interface ChatService {
    ChatRoomDto getOrCreateRoom(String saleListingId, String buyerUserId);
    List<ChatRoomDto> getMyRooms(String userId);
    List<ChatMessageDto> getMessages(String roomId, String userId);
    ChatMessageDto sendMessage(String roomId, String senderUserId, String message);
}
