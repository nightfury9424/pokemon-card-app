package com.fury.back.domain.card.dto;

import com.fury.back.domain.card.Card;
import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class CardSearchDto {

    private String cardId;
    private String officialCardCode;
    private String name;
    private String collectionNumber;
    private String rarityCode;
    private String language;
    private String superType;
    private String imageUrl;

    public static CardSearchDto from(Card card) {
        return CardSearchDto.builder()
                .cardId(card.getCardId())
                .officialCardCode(card.getOfficialCardCode())
                .name(card.getName())
                .collectionNumber(card.getCollectionNumber())
                .rarityCode(card.getRarityCode())
                .language(card.getLanguage())
                .superType(card.getSuperType())
                .imageUrl(card.getImageUrl())
                .build();
    }
}
