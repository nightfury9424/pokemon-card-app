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
                .cardImageUrl(card != null ? card.getImageUrl() : null)
                .rarityCode(card != null ? card.getRarityCode() : null)
                .build();
    }
}
