package com.fury.back.domain.trade.dto;

import com.fury.back.domain.card.Card;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.user.User;
import com.fury.back.storage.StorageKeyUrls;
import lombok.Builder;
import lombok.Getter;

import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.List;

@Getter
@Builder
public class TradePostDto {

    private String tradeId;
    private String cardId;
    private String assetId;
    private String title;
    private String description;
    private Integer price;
    private String imageUrl;
    private List<String> imageUrls;
    private String cardStatus;
    private String condition;
    private String gradingCompany;
    private String gradeValue;
    private String certNumber;
    private String status;
    private Integer viewCount;
    private String createdAt;

    // 판매자 정보
    private SellerDto seller;

    // 카드 정보 (조회 시 포함)
    private CardSummaryDto card;

    public static TradePostDto from(TradePost post) {
        return TradePostDto.builder()
                .tradeId(post.getTradeId())
                .cardId(post.getCardId())
                .assetId(post.getAssetId())
                .title(post.getTitle())
                .description(post.getDescription())
                .price(post.getPrice())
                .imageUrl(StorageKeyUrls.toProxyCsv(post.getImageUrl()))
                .imageUrls(splitImageUrls(post.getImageUrl()))
                .cardStatus(post.getCardStatus())
                .condition(post.getCondition())
                .gradingCompany(post.getGradingCompany())
                .gradeValue(post.getGradeValue())
                .certNumber(post.getCertNumber())
                .status(post.getStatus())
                .viewCount(post.getViewCount())
                .createdAt(post.getCreatedAt() != null ? post.getCreatedAt().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")) : null)
                .build();
    }

    public static TradePostDto fromWithDetails(TradePost post, User seller, Card card) {
        return TradePostDto.builder()
                .tradeId(post.getTradeId())
                .cardId(post.getCardId())
                .assetId(post.getAssetId())
                .title(post.getTitle())
                .description(post.getDescription())
                .price(post.getPrice())
                .imageUrl(StorageKeyUrls.toProxyCsv(post.getImageUrl()))
                .imageUrls(splitImageUrls(post.getImageUrl()))
                .cardStatus(post.getCardStatus())
                .condition(post.getCondition())
                .gradingCompany(post.getGradingCompany())
                .gradeValue(post.getGradeValue())
                .certNumber(post.getCertNumber())
                .status(post.getStatus())
                .viewCount(post.getViewCount())
                .createdAt(post.getCreatedAt() != null ? post.getCreatedAt().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")) : null)
                .seller(seller != null ? SellerDto.from(seller) : null)
                .card(card != null ? CardSummaryDto.from(card) : null)
                .build();
    }

    private static List<String> splitImageUrls(String imageUrl) {
        if (imageUrl == null || imageUrl.isBlank()) {
            return List.of();
        }
        // Phase 1-7: DB는 storage key 저장 → 응답에서 /api/images/secure/{key} proxy URL로 변환.
        return Arrays.stream(imageUrl.split(","))
                .map(String::trim)
                .filter(url -> !url.isBlank())
                .map(StorageKeyUrls::toProxyUrl)
                .toList();
    }

    @Getter
    @Builder
    public static class SellerDto {
        private String userId;
        private String nickname;
        private String profileImageUrl;

        public static SellerDto from(User user) {
            return SellerDto.builder()
                    .userId(user.getUserId())
                    .nickname(user.getNickname())
                    .profileImageUrl(user.getProfileImageUrl())
                    .build();
        }
    }

    @Getter
    @Builder
    public static class CardSummaryDto {
        private String cardId;
        private String name;
        private String rarityCode;
        private String imageUrl;
        private String jpScrydexRef;
        private String enScrydexRef;

        public static CardSummaryDto from(Card card) {
            return CardSummaryDto.builder()
                    .cardId(card.getCardId())
                    .name(card.getName())
                    .rarityCode(card.getRarityCode())
                    .imageUrl(card.getImageUrl())
                    .jpScrydexRef(card.getJpScrydexRef())
                    .enScrydexRef(card.getEnScrydexRef())
                    .build();
        }
    }
}
