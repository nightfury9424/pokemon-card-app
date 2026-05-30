package com.fury.back.domain.asset.dex;

import lombok.Builder;
import lombok.Getter;

import java.util.List;

/** 도감 응답 DTO. */
public class DexDto {

    /** GET /api/assets/dex — 메인 (그리드).
     *  2026-05-29 Codex MVP scope: limit 적용. totalProducts 는 전체, products 는 응답 N개. */
    @Getter
    @Builder
    public static class DexMain {
        private List<BoxItem> products;          // 응답된 limit 만큼
        private int totalProducts;               // 전체 product (KO visible > 0) — 268 기준
        private boolean hasMore;                 // products.size() < totalProducts
        private int ownedSeriesCount;            // 응답된 N개 중 보유 시리즈 수
        private int totalOwnedCards;             // 응답된 N개 합산 보유 종
        private int totalAvailableCards;         // 응답된 N개 합산 visible 카드
    }

    /** 도감 메인의 단일 박스. */
    @Getter
    @Builder
    public static class BoxItem {
        private String  productId;
        private String  productName;
        private int     totalKoVisible;       // 시리즈 visible 카드 수
        private int     ownedCount;           // 보유 종 수 (distinct card_id)
        private String  heroCardId;
        private String  heroCardName;
        private String  heroCardRarity;
        private String  heroCardImageUrl;     // backend resolveCardImageUrl
        private String  latestCardAt;         // 시리즈 최신 카드 created_at (정렬용)
    }

    /** GET /api/assets/dex/{productId} — 시리즈 상세. */
    @Getter
    @Builder
    public static class DexDetail {
        private String  productId;
        private String  productName;
        private int     totalKoVisible;
        private int     ownedCount;
        private List<DexCard> hits;     // up to 6 — products.dex_hit_card_ids CSV override, else auto top 4 (rarity priority + collection_number) fallback
        private List<DexCard> cards;    // 시리즈 visible 카드 전체 (collection_number asc)
    }

    @Getter
    @Builder
    public static class DexCard {
        private String  cardId;
        private String  name;
        private String  rarityCode;
        private String  collectionNumber;
        private String  imageUrl;
        private boolean owned;
        private int     quantity;       // 0 if not owned
    }
}
