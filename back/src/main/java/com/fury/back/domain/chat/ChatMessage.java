package com.fury.back.domain.chat;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "chat_messages")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class ChatMessage {

    @Id
    @Column(name = "chat_message_id", length = 50)
    private String chatMessageId;

    @Column(name = "chat_room_id", nullable = false, length = 50)
    private String chatRoomId;

    @Column(name = "sender_user_id", nullable = false, length = 50)
    private String senderUserId;

    @Column(name = "message", nullable = false, columnDefinition = "TEXT")
    private String message;

    @Column(name = "is_read", nullable = false)
    @Builder.Default
    private Boolean isRead = false;

    // Bundle 2-C: 'USER' (일반) / 'SYSTEM' (상태 변경 안내, 사기 주의 등 자동 메시지).
    // SYSTEM은 sender_user_id='SYSTEM' 특수값 + user lookup skip.
    @Column(name = "message_type", nullable = false, length = 20)
    @Builder.Default
    private String messageType = "USER";

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }

    public void markAsRead() {
        this.isRead = true;
    }
}
