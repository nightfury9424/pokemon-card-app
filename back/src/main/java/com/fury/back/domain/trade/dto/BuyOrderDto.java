package com.fury.back.domain.trade.dto;

import com.fury.back.domain.card.Card;
import com.fury.back.domain.trade.BuyOrder;
import com.fury.back.domain.user.User;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder(toBuilder = true)
public class BuyOrderDto {
    private String buyOrderId;
    private String buyerId;
    private String buyerNickname;
    private String cardId;
    private String cardName;
    private String cardImageUrl;
    private String rarityCode;
    private Integer bidPrice;
    private Integer qty;
    private String cardStatus;       // RAW / GRADED
    private String gradingCompany;
    private String gradeValue;
    private String memo;
    private String status;
    private String matchedTradeId;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    public static BuyOrderDto from(BuyOrder o) {
        return BuyOrderDto.builder()
                .buyOrderId(o.getBuyOrderId())
                .buyerId(o.getBuyerId())
                .cardId(o.getCardId())
                .bidPrice(o.getBidPrice())
                .qty(o.getQty())
                .cardStatus(o.getCardStatus())
                .gradingCompany(o.getGradingCompany())
                .gradeValue(o.getGradeValue())
                .memo(o.getMemo())
                .status(o.getStatus())
                .matchedTradeId(o.getMatchedTradeId())
                .createdAt(o.getCreatedAt())
                .updatedAt(o.getUpdatedAt())
                .build();
    }

    public static BuyOrderDto fromWithDetails(BuyOrder o, User buyer, Card card) {
        return from(o).toBuilder()
                .buyerNickname(buyer != null ? buyer.getNickname() : null)
                .cardName(card != null ? card.getName() : null)
                // Fix (2026-05-20): card.getImageUrl()은 pokemonkorea.co.kr URL (deprecated, Flutter
                // CardImage가 "이미지 없음" 처리). scrydex CDN URL 직접 조립 (jp 우선, en fallback).
                .cardImageUrl(resolveCardImageUrl(card))
                .rarityCode(card != null ? card.getRarityCode() : null)
                .build();
    }

    /** Card → scrydex CDN URL (jp 우선, en fallback, NO_/null이면 null). */
    private static String resolveCardImageUrl(Card card) {
        if (card == null) return null;
        final String jpRef = card.getJpScrydexRef();
        if (jpRef != null && !jpRef.isBlank() && !jpRef.startsWith("NO_")) {
            return "https://images.scrydex.com/pokemon/" + jpRef + "/medium";
        }
        final String enRef = card.getEnScrydexRef();
        if (enRef != null && !enRef.isBlank() && !enRef.startsWith("NO_")) {
            return "https://images.scrydex.com/pokemon/" + enRef + "/medium";
        }
        return null;
    }
}
