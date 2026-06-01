package com.fury.back.domain.chat;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "chat_rooms")
// 2026-05-28: BuyOrder 양방향 채팅 추가. uniqueConstraints는 partial index로 SQL 마이그레이션 관리
// (buy_order_chat_room_migration.sql). sale_listing_id NOT NULL row vs buy_order_id NOT NULL row를
// 분리해 각각 unique. JPA 어노테이션 unique는 partial 표현 불가라 SQL에서 직접 정의.
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class ChatRoom {

    @Id
    @Column(name = "chat_room_id", length = 50)
    private String chatRoomId;

    /** SALE chat: TradePost.id 참조. BUY chat: NULL. (buy_order_id 와 XOR — DB CHECK 강제) */
    @Column(name = "sale_listing_id", length = 50)
    private String saleListingId;

    /** BUY chat: BuyOrder.id 참조. SALE chat: NULL. */
    @Column(name = "buy_order_id", length = 50)
    private String buyOrderId;

    /** 카드 팔려는 사람 user_id. SALE: TradePost.sellerId. BUY: 채팅 시작자(잠재 판매자). */
    @Column(name = "seller_user_id", nullable = false, length = 50)
    private String sellerUserId;

    /** 카드 사려는 사람 user_id. SALE: 채팅 시작자(구매 의향). BUY: BuyOrder.buyerId(작성자). */
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
        // 2026-05-28: sale_listing_id ⊕ buy_order_id 는 정확히 하나만 NOT NULL.
        // DB CHECK chk_chat_rooms_listing_xor 가 최종 안전망이지만 빠른 fail + 명확한 메시지를 위해
        // entity 단에서 먼저 가드. 빌더가 둘 다 set 또는 둘 다 null 상태로 saveAndFlush 호출 시 차단.
        final boolean hasSale = saleListingId != null && !saleListingId.isBlank();
        final boolean hasBuy = buyOrderId != null && !buyOrderId.isBlank();
        if (hasSale == hasBuy) {
            throw new IllegalStateException(
                    "ChatRoom requires exactly one of saleListingId or buyOrderId — got sale=" + hasSale + ", buy=" + hasBuy);
        }
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
