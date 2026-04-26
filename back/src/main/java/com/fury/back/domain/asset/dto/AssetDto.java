package com.fury.back.domain.asset.dto;

import com.fury.back.domain.asset.Asset;
import com.fury.back.domain.card.Card;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Getter
@Builder(toBuilder = true)
public class AssetDto {

    private String assetId;
    private String userId;
    private String cardId;
    private Integer quantity;
    private Integer purchasePrice;
    private String cardStatus;
    private String gradingCompany;
    private String gradeValue;
    private String certNumber;
    private String memo;
    private LocalDate purchasedAt;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    // 카드 정보 (목록 조회 시 포함)
    private CardInfo card;

    @Getter
    @Builder
    public static class CardInfo {
        private String cardId;
        private String name;
        private String rarityCode;
        private String imageUrl;
        private String jpScrydexRef;
        private String enScrydexRef;

        public static CardInfo from(Card c) {
            return CardInfo.builder()
                    .cardId(c.getCardId())
                    .name(c.getName())
                    .rarityCode(c.getRarityCode())
                    .imageUrl(c.getImageUrl())
                    .jpScrydexRef(c.getJpScrydexRef())
                    .enScrydexRef(c.getEnScrydexRef())
                    .build();
        }
    }

    public static AssetDto from(Asset asset) {
        return AssetDto.builder()
                .assetId(asset.getAssetId())
                .userId(asset.getUserId())
                .cardId(asset.getCardId())
                .quantity(asset.getQuantity())
                .purchasePrice(asset.getPurchasePrice())
                .cardStatus(asset.getCardStatus())
                .gradingCompany(asset.getGradingCompany())
                .gradeValue(asset.getGradeValue())
                .certNumber(asset.getCertNumber())
                .memo(asset.getMemo())
                .purchasedAt(asset.getPurchasedAt())
                .createdAt(asset.getCreatedAt())
                .updatedAt(asset.getUpdatedAt())
                .build();
    }

    public static AssetDto fromWithCard(Asset asset, Card card) {
        return from(asset).toBuilder()
                .card(card != null ? CardInfo.from(card) : null)
                .build();
    }
}
