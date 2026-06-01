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

    /**
     * #62 (2026-05-20): scrydex hotlink 직접 조립 제거. caller (Service layer)에서
     * CardCdnUrls.forCard(card)로 S3 URL을 미리 만들어 String으로 주입.
     * DTO는 plain string만 받음 (Spring Component 의존성 없음).
     */
    public static BuyOrderDto fromWithDetails(BuyOrder o, User buyer, Card card, String cardImageUrl) {
        return from(o).toBuilder()
                .buyerNickname(buyer != null ? buyer.getNickname() : null)
                .cardName(card != null ? card.getName() : null)
                .cardImageUrl(cardImageUrl)
                .rarityCode(card != null ? card.getRarityCode() : null)
                .build();
    }
}
