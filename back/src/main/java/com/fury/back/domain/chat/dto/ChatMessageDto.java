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
    /** Bundle 2-C: 'USER' or 'SYSTEM'. 프론트 bubble 분기용. */
    private String messageType;
    private LocalDateTime createdAt;

    public static ChatMessageDto from(ChatMessage msg, String senderNickname, String senderProfileUrl) {
        // Bundle 2-C: SYSTEM 메시지는 user lookup skip — nickname="시스템" 고정, profile null.
        final boolean isSystem = "SYSTEM".equals(msg.getMessageType());
        return ChatMessageDto.builder()
                .chatMessageId(msg.getChatMessageId())
                .chatRoomId(msg.getChatRoomId())
                .senderUserId(msg.getSenderUserId())
                .senderNickname(isSystem ? "시스템" : senderNickname)
                .senderProfileImageUrl(isSystem ? null : senderProfileUrl)
                .message(msg.getMessage())
                .isRead(msg.getIsRead())
                .messageType(msg.getMessageType())
                .createdAt(msg.getCreatedAt())
                .build();
    }
}
