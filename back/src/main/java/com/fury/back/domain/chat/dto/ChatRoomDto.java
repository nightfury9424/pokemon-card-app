package com.fury.back.domain.chat.dto;

import com.fury.back.domain.chat.ChatRoom;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

/**
 * 채팅방 DTO — SALE chat (TradePost 기반) / BUY chat (BuyOrder 기반) 양쪽 표현.
 *
 * <p>{@code contextType} 으로 프론트가 라벨([판매]/[구매]) + context card 분기.
 * {@code tradeTitle/tradePrice/tradeStatus} 필드는 SALE/BUY 양쪽에서 의미를 재사용 — backward compat
 * 위해 기존 필드명 유지 (Codex C 권장). SALE 에선 TradePost.{title, price, status},
 * BUY 에선 카드명, BuyOrder.bidPrice, BuyOrder.status 를 담는다.</p>
 *
 * <p>정적 팩토리는 {@link #fromSale}, {@link #fromBuy} 둘 — 단일 시그니처 확장 시 positional param
 * 혼동 위험 큼 (Codex C, "tradePrice 와 bidPrice 섞임").</p>
 */
@Getter
@Builder
public class ChatRoomDto {
    private String chatRoomId;

    /** 'SALE' = TradePost 기반, 'BUY' = BuyOrder 기반. 프론트 라벨 chip 분기. */
    private String contextType;

    /** SALE chat: TradePost.id. BUY chat: null. */
    private String saleListingId;

    /** BUY chat: BuyOrder.id. SALE chat: null. */
    private String buyOrderId;

    /** SALE: TradePost.title. BUY: 카드명 fallback (BuyOrder는 title 컬럼 없음). */
    private String tradeTitle;

    /** SALE: 사용자 업로드 trade 사진 (StorageKeyUrls). BUY: null (BuyOrder 사진 X). */
    private String tradeImageUrl;

    private String otherUserId;
    private String otherUserNickname;
    private String otherUserProfileImageUrl;

    /**
     * 2026-05-29: 프론트에서 BUY chat 의 BuyOrder owner 판정용.
     * SALE: TradePost.sellerId. BUY: 채팅 시작자(잠재 판매자).
     */
    private String sellerUserId;
    /**
     * 2026-05-29: 프론트에서 SALE chat 의 buyer 판정용 (이전엔 _trade fetch 후 sellerId 비교만).
     * SALE: 채팅 시작자(구매 의향). BUY: BuyOrder.buyerId(작성자) — status 변경 권한자.
     */
    private String buyerUserId;
    private String lastMessage;
    private LocalDateTime lastMessageAt;
    private long unreadCount;
    private LocalDateTime createdAt;

    /** SALE: TradePost.status (OPEN/RESERVED/COMPLETED/DELETED). BUY: BuyOrder.status (OPEN/MATCHED/CANCELED). */
    private String tradeStatus;

    /** SALE: TradePost.price. BUY: BuyOrder.bidPrice. */
    private Integer tradePrice;

    /** Card master 이미지 URL (CardCdnUrls.forCard). SALE/BUY 동일 패턴. */
    private String cardImageUrl;

    /** 2026-05-28 신규 — 카드명 (tradeTitle 과 별개로 명시적 노출). */
    private String cardName;

    /**
     * SALE chat 용 정적 팩토리 — TradePost 기반.
     * 기존 {@code from()} 의 의미 명확화 rename (Codex C).
     */
    public static ChatRoomDto fromSale(ChatRoom room, String myUserId,
                                       String tradeTitle, String tradeImageUrl,
                                       String otherNickname, String otherProfileUrl,
                                       long unreadCount,
                                       String tradeStatus, Integer tradePrice,
                                       String cardImageUrl, String cardName) {
        String otherUserId = myUserId.equals(room.getBuyerUserId())
                ? room.getSellerUserId()
                : room.getBuyerUserId();
        return ChatRoomDto.builder()
                .chatRoomId(room.getChatRoomId())
                .contextType("SALE")
                .saleListingId(room.getSaleListingId())
                .buyOrderId(null)
                .tradeTitle(tradeTitle)
                .tradeImageUrl(tradeImageUrl)
                .otherUserId(otherUserId)
                .otherUserNickname(otherNickname)
                .otherUserProfileImageUrl(otherProfileUrl)
                .sellerUserId(room.getSellerUserId())
                .buyerUserId(room.getBuyerUserId())
                .lastMessage(room.getLastMessage())
                .lastMessageAt(room.getLastMessageAt())
                .unreadCount(unreadCount)
                .createdAt(room.getCreatedAt())
                .tradeStatus(tradeStatus)
                .tradePrice(tradePrice)
                .cardImageUrl(cardImageUrl)
                .cardName(cardName)
                .build();
    }

    /**
     * BUY chat 용 정적 팩토리 — BuyOrder 기반.
     * {@code tradeTitle} 은 카드명 fallback, {@code tradePrice} 는 BuyOrder.bidPrice,
     * {@code tradeStatus} 는 BuyOrder.status. {@code tradeImageUrl} 은 null
     * (BuyOrder 는 사용자 업로드 사진 컬럼 없음 — cardImageUrl 만 사용).
     */
    public static ChatRoomDto fromBuy(ChatRoom room, String myUserId,
                                      String cardName, String otherNickname, String otherProfileUrl,
                                      long unreadCount,
                                      String buyOrderStatus, Integer bidPrice,
                                      String cardImageUrl) {
        String otherUserId = myUserId.equals(room.getBuyerUserId())
                ? room.getSellerUserId()
                : room.getBuyerUserId();
        return ChatRoomDto.builder()
                .chatRoomId(room.getChatRoomId())
                .contextType("BUY")
                .saleListingId(null)
                .buyOrderId(room.getBuyOrderId())
                .tradeTitle(cardName)
                .tradeImageUrl(null)
                .otherUserId(otherUserId)
                .otherUserNickname(otherNickname)
                .otherUserProfileImageUrl(otherProfileUrl)
                .sellerUserId(room.getSellerUserId())
                .buyerUserId(room.getBuyerUserId())
                .lastMessage(room.getLastMessage())
                .lastMessageAt(room.getLastMessageAt())
                .unreadCount(unreadCount)
                .createdAt(room.getCreatedAt())
                .tradeStatus(buyOrderStatus)
                .tradePrice(bidPrice)
                .cardImageUrl(cardImageUrl)
                .cardName(cardName)
                .build();
    }
}
