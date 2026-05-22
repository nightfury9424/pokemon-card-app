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
    // Bundle 2-A: 거래 미니카드용. trade 또는 card 매칭 부재 시 모두 null로 내림 (stale-safe).
    /** TradePost.status — OPEN / RESERVED / COMPLETED / DELETED (CANCELED는 판매글에 부적합 — 제거됨 2026-05-22) */
    private String tradeStatus;
    /** TradePost.price — 콤마+원 포맷은 프론트에서 처리 */
    private Integer tradePrice;
    /** Card master 이미지 URL (CardCdnUrls.forCard). 사용자 업로드 trade 사진 X. */
    private String cardImageUrl;

    public static ChatRoomDto from(ChatRoom room, String myUserId,
                                   String tradeTitle, String tradeImageUrl,
                                   String otherNickname, String otherProfileUrl,
                                   long unreadCount,
                                   String tradeStatus, Integer tradePrice, String cardImageUrl) {
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
                .tradeStatus(tradeStatus)
                .tradePrice(tradePrice)
                .cardImageUrl(cardImageUrl)
                .build();
    }
}
