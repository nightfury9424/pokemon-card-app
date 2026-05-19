package com.fury.back.storage;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import com.fury.back.domain.card.Card;

/**
 * 카드 마스터 이미지 URL helper — S3 cards/v1 prefix.
 *
 * <p>2026-05-20 #62: BuyOrderDto.resolveCardImageUrl (static scrydex hotlink)을
 * 정식 Spring Component로 분리. 신규 호출처는 이 Component 주입 후 사용.
 *
 * <p>우선순위:
 *   jp ref valid → /jp/{cardId}.png
 *   en ref valid → /en/{cardId}.png
 *   둘 다 NO_/null → /special/{cardId}.png (메타몽 등)
 *   cardId 자체 null → null
 */
@Component
public class CardCdnUrls {

    private final String base;

    public CardCdnUrls(@Value("${app.card-cdn.base-url}") String baseUrl) {
        // trailing slash 트리밍
        this.base = baseUrl.endsWith("/")
                ? baseUrl.substring(0, baseUrl.length() - 1)
                : baseUrl;
    }

    /** Card → cards/v1/{lang}/{cardId}.png 또는 cards/v1/special/{cardId}.png. */
    public String forCard(Card card) {
        if (card == null) return null;
        final String cardId = card.getCardId();
        if (cardId == null || cardId.isBlank()) return null;
        if (hasValidRef(card.getJpScrydexRef())) return base + "/jp/" + cardId + ".png";
        if (hasValidRef(card.getEnScrydexRef())) return base + "/en/" + cardId + ".png";
        return base + "/special/" + cardId + ".png";
    }

    private static boolean hasValidRef(String ref) {
        return ref != null && !ref.isBlank() && !ref.startsWith("NO_");
    }
}
