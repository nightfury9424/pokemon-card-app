package com.fury.back.domain.card.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.price.PriceLabelType;
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
    private Integer koEstimatedPrice;
    private String koPriceBasis;
    // 전일 KO_ESTIMATED 가격 + 변동률 (캐러셀/리스트 변동률 표시용)
    // REFACTOR_2026-05-12.md 4차-Round3.
    private Integer yesterdayPrice;
    private Double gainPct;
    // Turn D-3 (2026-05-17): recent ranking 전용 — 변동일 가격과 현재가 분리.
    // 기존 top-gainers/top-losers는 영향 없음 (mapGainerRows 미설정).
    private Integer currentPrice;       // 최신 KO_ESTIMATED row 가격
    private Integer moveDatePrice;      // 변동 발생일 KO 가격 (audit.ko_price)
    private Integer prevPrice;          // 변동 전 KO 가격 (prev_audit snapshot)
    private Integer changeAmount;       // moveDatePrice - prevPrice
    private java.time.LocalDate moveDate; // 변동 발생일
    @JsonProperty("isPromoExclusive")
    private boolean isPromoExclusive;
    private String promoType;
    // 표시 라벨 (PriceLabelType): DOMESTIC_REAL / DOMESTIC_FEW / ESTIMATED / OVERSEAS_REF.
    // 가격값과 무관한 display-layer 필드. 화면에 보이는 KO 가격 분기(isPromoExclusive)와 일치.
    private String koPriceLabelType;

    // 거래 리스트 row 표시용 engagement 카운트 (Phase 1). null 가능 — list/ranking 응답에서만 enrich.
    // activeSellCount = TradePost WHERE status IN (OPEN, RESERVED) — 거래 가능 매도 호가 수.
    // activeBuyCount = BuyOrder WHERE status = OPEN — 활성 매수 호가 수.
    // interestCount = CardInterest count — 관심(찜) 표시 수.
    private Integer activeSellCount;
    private Integer activeBuyCount;
    private Integer interestCount;

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
                .isPromoExclusive(card.isPromoExclusive())
                .promoType(card.getPromoType() != null ? card.getPromoType().name() : null)
                .koPriceLabelType(PriceLabelType.resolve(card.isPromoExclusive(), null).name())
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
                    .isPromoExclusive(dto.isPromoExclusive)
                    .promoType(dto.promoType)
                    .koPriceLabelType(dto.koPriceLabelType)
                    .productName(product.getName())
                    .seriesName(product.getSeriesName())
                    .productType(product.getProductType())
                    .build();
        }
        return dto;
    }
}
