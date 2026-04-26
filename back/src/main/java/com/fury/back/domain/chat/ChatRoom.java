package com.fury.back.domain.chat;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "chat_rooms")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class ChatRoom {

    @Id
    @Column(name = "chat_room_id", length = 50)
    private String chatRoomId;

    @Column(name = "sale_listing_id", nullable = false, length = 50)
    private String saleListingId;

    @Column(name = "seller_user_id", nullable = false, length = 50)
    private String sellerUserId;

    @Column(name = "buyer_user_id", nullable = false, length = 50)
    private String buyerUserId;

    @Column(name = "last_message", columnDefinition = "TEXT")
    private String lastMessage;

    @Column(name = "last_message_at")
    private LocalDateTime lastMessageAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }

    public void updateLastMessage(String message) {
        this.lastMessage = message;
        this.lastMessageAt = LocalDateTime.now();
    }
}
