package com.fury.back.domain.chat.dto;

import com.fury.back.domain.chat.ChatRoom;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class ChatRoomDto {
    private String chatRoomId;
    private String saleListingId;
    private String tradeTitle;
    private String tradeImageUrl;
    private String otherUserId;
    private String otherUserNickname;
    private String otherUserProfileImageUrl;
    private String lastMessage;
    private LocalDateTime lastMessageAt;
    private long unreadCount;
    private LocalDateTime createdAt;

    public static ChatRoomDto from(ChatRoom room, String myUserId,
                                   String tradeTitle, String tradeImageUrl,
                                   String otherNickname, String otherProfileUrl,
                                   long unreadCount) {
        String otherUserId = myUserId.equals(room.getBuyerUserId())
                ? room.getSellerUserId()
                : room.getBuyerUserId();
        return ChatRoomDto.builder()
                .chatRoomId(room.getChatRoomId())
                .saleListingId(room.getSaleListingId())
                .tradeTitle(tradeTitle)
                .tradeImageUrl(tradeImageUrl)
                .otherUserId(otherUserId)
                .otherUserNickname(otherNickname)
                .otherUserProfileImageUrl(otherProfileUrl)
                .lastMessage(room.getLastMessage())
                .lastMessageAt(room.getLastMessageAt())
                .unreadCount(unreadCount)
                .createdAt(room.getCreatedAt())
                .build();
    }
}
