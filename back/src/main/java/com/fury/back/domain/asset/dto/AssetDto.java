package com.fury.back.domain.asset.dto;

import com.fury.back.domain.asset.Asset;
import com.fury.back.domain.card.Card;
import lombok.Builder;
import lombok.Getter;

import java.math.BigDecimal;
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
    private String language;
    private String cardStatus;
    private String gradingCompany;
    private String gradeValue;
    private String certNumber;
    private BigDecimal estimatedGrade;
    private BigDecimal centeringScore;
    private BigDecimal cornerScore;
    private BigDecimal surfaceScore;
    private BigDecimal whiteningScore;
    private String centeringRatio;
    private BigDecimal detectionConfidence;
    private LocalDateTime gradingAnalyzedAt;
    private String memo;
    private LocalDate purchasedAt;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private Boolean isSelling;
    private String activeTradeId;
    /** asset.language 기준 환산 가격(KRW). KO=koEstimated, EN/JP=scrydex raw × 환율. */
    private Integer displayPrice;
    /**
     * displayPrice의 출처. UI 라벨/안내문에 사용.
     * - "KO_ESTIMATED" / "RAW" : asset.language별 raw 시세 적용
     * - "PSA10" : GRADED PSA10 시세 직접 사용
     * - "RAW_FALLBACK" : GRADED인데 PSA10 시세 없어서 RAW로 폴백
     * - null : 데이터 없음
     */
    private String displayPriceBasis;

    // 카드 정보 (목록 조회 시 포함)
    private CardInfo card;

    @Getter
    @Builder
    public static class CardInfo {
        private String cardId;
        private String name;
        private String rarityCode;
        private String imageUrl;
        private String language;
        private String jpScrydexRef;
        private String enScrydexRef;

        public static CardInfo from(Card c) {
            return CardInfo.builder()
                    .cardId(c.getCardId())
                    .name(c.getName())
                    .rarityCode(c.getRarityCode())
                    .imageUrl(c.getImageUrl())
                    .language(c.getLanguage())
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
                .language(asset.getLanguage())
                .cardStatus(asset.getCardStatus())
                .gradingCompany(asset.getGradingCompany())
                .gradeValue(asset.getGradeValue())
                .certNumber(asset.getCertNumber())
                .estimatedGrade(asset.getEstimatedGrade())
                .centeringScore(asset.getCenteringScore())
                .cornerScore(asset.getCornerScore())
                .surfaceScore(asset.getSurfaceScore())
                .whiteningScore(asset.getWhiteningScore())
                .centeringRatio(asset.getCenteringRatio())
                .detectionConfidence(asset.getDetectionConfidence())
                .gradingAnalyzedAt(asset.getGradingAnalyzedAt())
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

    public static AssetDto fromWithCardAndSelling(Asset asset, Card card, String activeTradeId) {
        return fromWithCard(asset, card).toBuilder()
                .isSelling(activeTradeId != null)
                .activeTradeId(activeTradeId)
                .build();
    }

    public record GradingResultRequest(
            BigDecimal estimatedGrade,
            BigDecimal centeringScore,
            BigDecimal cornerScore,
            BigDecimal surfaceScore,
            BigDecimal whiteningScore,
            String centeringRatio,
            BigDecimal detectionConfidence,
            String appAnalysisId
    ) {
    }
}
