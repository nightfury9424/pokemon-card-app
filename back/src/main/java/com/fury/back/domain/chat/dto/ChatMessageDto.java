package com.fury.back.domain.chat.dto;

import com.fury.back.domain.chat.ChatMessage;
import com.fury.back.storage.StorageKeyUrls;
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
    /**
     * 메시지 본문.
     *   - USER/SYSTEM/STATE_CHANGED: 평문
     *   - IMAGE: proxy URL (`/api/images/secure/chat/{roomId}/{uuid}.{ext}`) — DB에는 storage key 저장,
     *            DTO 변환 시 URL 로 노출 (Codex B 권장 — key leak 방지).
     */
    private String message;
    private Boolean isRead;
    /** 'USER' / 'SYSTEM' / 'STATE_CHANGED' / 'IMAGE' (2026-05-28 신규). 프론트 bubble 분기. */
    private String messageType;
    private LocalDateTime createdAt;

    public static ChatMessageDto from(ChatMessage msg, String senderNickname, String senderProfileUrl) {
        // Bundle 2-C: SYSTEM 메시지는 user lookup skip — nickname="시스템" 고정, profile null.
        final boolean isSystem = "SYSTEM".equals(msg.getMessageType());
        final boolean isImage = "IMAGE".equals(msg.getMessageType());
        // 2026-05-28 IMAGE: DB의 storage key 를 proxy URL 로 변환해서 응답.
        // 클라이언트는 AuthImage(JWT) 로 fetch — public read 차단 (참여자 검증은 proxy controller).
        final String body = isImage
                ? StorageKeyUrls.toProxyUrl(msg.getMessage())
                : msg.getMessage();
        return ChatMessageDto.builder()
                .chatMessageId(msg.getChatMessageId())
                .chatRoomId(msg.getChatRoomId())
                .senderUserId(msg.getSenderUserId())
                .senderNickname(isSystem ? "시스템" : senderNickname)
                .senderProfileImageUrl(isSystem ? null : senderProfileUrl)
                .message(body)
                .isRead(msg.getIsRead())
                .messageType(msg.getMessageType())
                .createdAt(msg.getCreatedAt())
                .build();
    }
}
