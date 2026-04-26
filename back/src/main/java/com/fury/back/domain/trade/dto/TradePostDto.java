package com.fury.back.domain.trade.dto;

import com.fury.back.domain.card.Card;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.user.User;
import lombok.Builder;
import lombok.Getter;

import java.time.format.DateTimeFormatter;

@Getter
@Builder
public class TradePostDto {

    private String tradeId;
    private String cardId;
    private String title;
    private String description;
    private Integer price;
    private String imageUrl;
    private String cardStatus;
    private String gradingCompany;
    private String gradeValue;
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
                .title(post.getTitle())
                .description(post.getDescription())
                .price(post.getPrice())
                .imageUrl(post.getImageUrl())
                .cardStatus(post.getCardStatus())
                .gradingCompany(post.getGradingCompany())
                .gradeValue(post.getGradeValue())
                .status(post.getStatus())
                .viewCount(post.getViewCount())
                .createdAt(post.getCreatedAt().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")))
                .build();
    }

    public static TradePostDto fromWithDetails(TradePost post, User seller, Card card) {
        return TradePostDto.builder()
                .tradeId(post.getTradeId())
                .cardId(post.getCardId())
                .title(post.getTitle())
                .description(post.getDescription())
                .price(post.getPrice())
                .imageUrl(post.getImageUrl())
                .cardStatus(post.getCardStatus())
                .gradingCompany(post.getGradingCompany())
                .gradeValue(post.getGradeValue())
                .status(post.getStatus())
                .viewCount(post.getViewCount())
                .createdAt(post.getCreatedAt().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm")))
                .seller(seller != null ? SellerDto.from(seller) : null)
                .card(card != null ? CardSummaryDto.from(card) : null)
                .build();
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

        public static CardSummaryDto from(Card card) {
            return CardSummaryDto.builder()
                    .cardId(card.getCardId())
                    .name(card.getName())
                    .rarityCode(card.getRarityCode())
                    .imageUrl(card.getImageUrl())
                    .build();
        }
    }
}
