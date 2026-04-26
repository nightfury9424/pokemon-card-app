package com.fury.back.domain.chat.dto;

import com.fury.back.domain.chat.ChatMessage;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class ChatMessageDto {
    private String chatMessageId;
    private String chatRoomId;
    private String senderUserId;
    private String senderNickname;
    private String senderProfileImageUrl;
    private String message;
    private Boolean isRead;
    private LocalDateTime createdAt;

    public static ChatMessageDto from(ChatMessage msg, String senderNickname, String senderProfileUrl) {
        return ChatMessageDto.builder()
                .chatMessageId(msg.getChatMessageId())
                .chatRoomId(msg.getChatRoomId())
                .senderUserId(msg.getSenderUserId())
                .senderNickname(senderNickname)
                .senderProfileImageUrl(senderProfileUrl)
                .message(msg.getMessage())
                .isRead(msg.getIsRead())
                .createdAt(msg.getCreatedAt())
                .build();
    }
}
