package com.fury.back.domain.product;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "products")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Product {

    @Id
    @Column(name = "product_id", length = 50)
    private String productId;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    @Column(name = "series_name", length = 200)
    private String seriesName;

    // BOOSTER / DECK / PROMO / SPECIAL
    @Column(name = "product_type", length = 30)
    private String productType;

    // KO / JA / EN
    @Column(name = "language", nullable = false, length = 10)
    private String language;

    @Column(name = "image_url", length = 500)
    private String imageUrl;

    /**
     * 도감 힛카드 CSV override (CRD_xxx,CRD_yyy,...). 순서 = display 순서. NULL = 자동 fallback.
     * DexService 가 NULL/blank 시 기존 rarity priority + collection_number top 4 산출.
     * 2026-05-30 Cycle 2 — 컬렉션형 시리즈 (VSTAR/테라스탈/151/VMAX 클라이맥스) max 6장 허용.
     */
    @Column(name = "dex_hit_card_ids", columnDefinition = "text")
    private String dexHitCardIds;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
        this.updatedAt = LocalDateTime.now();
    }

    @PreUpdate
    protected void onUpdate() {
        this.updatedAt = LocalDateTime.now();
    }
}
