package com.fury.back.domain.chat;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(
        name = "chat_rooms",
        uniqueConstraints = @UniqueConstraint(
                name = "uq_chat_rooms_sale_buyer",
                columnNames = {"sale_listing_id", "buyer_user_id"}
        )
)
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

    /** 채팅방 나가기 / 차단 시 buyer 측에 set. null 이면 buyer 목록에 노출. */
    @Column(name = "buyer_hidden_at")
    private LocalDateTime buyerHiddenAt;

    /** 채팅방 나가기 / 차단 시 seller 측에 set. null 이면 seller 목록에 노출. */
    @Column(name = "seller_hidden_at")
    private LocalDateTime sellerHiddenAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }

    public void updateLastMessage(String message) {
        this.lastMessage = message;
        this.lastMessageAt = LocalDateTime.now();
    }

    /** 호출자가 buyer/seller 어느 쪽이든 본인 hidden_at 만 set. 둘 다 아니면 no-op. */
    public void hideForUser(String userId) {
        if (userId.equals(this.buyerUserId)) {
            this.buyerHiddenAt = LocalDateTime.now();
        } else if (userId.equals(this.sellerUserId)) {
            this.sellerHiddenAt = LocalDateTime.now();
        }
    }

    /** Phase 1 hotfix: 본인 hidden_at clear — getOrCreateRoom 재진입 시 본인 측 복구. */
    public void clearHiddenForUser(String userId) {
        if (userId.equals(this.buyerUserId)) {
            this.buyerHiddenAt = null;
        } else if (userId.equals(this.sellerUserId)) {
            this.sellerHiddenAt = null;
        }
    }
}
