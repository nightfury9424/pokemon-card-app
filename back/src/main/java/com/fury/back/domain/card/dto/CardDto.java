package com.fury.back.domain.card.dto;

import com.fury.back.domain.card.Card;
import com.fury.back.domain.price.PriceSnapshot;
import lombok.Builder;
import lombok.Getter;

@Getter
@Builder(toBuilder = true)
public class CardDto {

    private String cardId;
    private String productId;
    private String officialCardCode;
    private String name;
    private String collectionNumber;
    private String rarityCode;
    private String language;
    private String superType;
    private String subType;
    private String illustrator;
    private String imageUrl;
    private String enScrydexRef;
    private String jpScrydexRef;
    private String productName;
    private String seriesName;
    private String productType;
    private Integer latestPrice;
    private String latestTradedAt;

    public static CardDto from(Card card) {
        return CardDto.builder()
                .cardId(card.getCardId())
                .productId(card.getProductId())
                .officialCardCode(card.getOfficialCardCode())
                .name(card.getName())
                .collectionNumber(card.getCollectionNumber())
                .rarityCode(card.getRarityCode())
                .language(card.getLanguage())
                .superType(card.getSuperType())
                .subType(card.getSubType())
                .illustrator(card.getIllustrator())
                .imageUrl(card.getImageUrl())
                .enScrydexRef(card.getEnScrydexRef())
                .jpScrydexRef(card.getJpScrydexRef())
                .build();
    }

    public static CardDto fromWithPrice(Card card, PriceSnapshot snapshot) {
        return from(card).toBuilder()
                .latestPrice(snapshot != null ? snapshot.getPrice() : null)
                .latestTradedAt(snapshot != null && snapshot.getTradedAt() != null
                        ? snapshot.getTradedAt().toString() : null)
                .build();
    }

    public static CardDto from(Card card, com.fury.back.domain.product.Product product) {
        CardDto dto = from(card);
        if (product != null) {
            return CardDto.builder()
                    .cardId(dto.cardId).productId(dto.productId).officialCardCode(dto.officialCardCode)
                    .name(dto.name).collectionNumber(dto.collectionNumber)
                    .rarityCode(dto.rarityCode).language(dto.language).superType(dto.superType)
                    .subType(dto.subType).illustrator(dto.illustrator).imageUrl(dto.imageUrl)
                    .enScrydexRef(dto.enScrydexRef).jpScrydexRef(dto.jpScrydexRef)
                    .productName(product.getName())
                    .seriesName(product.getSeriesName())
                    .productType(product.getProductType())
                    .build();
        }
        return dto;
    }
}
