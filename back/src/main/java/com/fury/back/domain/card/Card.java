package com.fury.back.domain.card;

import jakarta.persistence.*;
import lombok.*;
import org.hibernate.annotations.SQLRestriction;

import java.time.LocalDateTime;

@Entity
@Table(name = "cards")
@SQLRestriction("is_visible = true")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Card {

    @Id
    @Column(name = "card_id", length = 50)
    private String cardId;

    @Column(name = "product_id", nullable = false, length = 50)
    private String productId;

    @Column(name = "official_card_code", length = 100)
    private String officialCardCode;

    @Column(name = "name", nullable = false, length = 200)
    private String name;

    // ex: 001/165
    @Column(name = "collection_number", length = 50)
    private String collectionNumber;

    // nullable - 레어도 없는 카드 존재
    @Column(name = "rarity_code", length = 50)
    private String rarityCode;

    // KO / JA / EN
    @Column(name = "language", nullable = false, length = 10)
    private String language;

    // POKEMON / TRAINER / ENERGY
    @Column(name = "super_type", nullable = false, length = 30)
    private String superType;

    // ITEM / SUPPORTER / STADIUM / TOOL / BASIC / SPECIAL ...
    @Column(name = "sub_type", length = 50)
    private String subType;

    @Column(name = "illustrator", length = 100)
    private String illustrator;

    @Column(name = "image_url", length = 500)
    private String imageUrl;

    @Column(name = "local_image_path", length = 500)
    private String localImagePath;

    @Column(name = "en_scrydex_ref", length = 100)
    private String enScrydexRef;

    @Column(name = "jp_scrydex_ref", length = 200)
    private String jpScrydexRef;

    @Builder.Default
    @Column(name = "is_promo_exclusive", nullable = false)
    private boolean isPromoExclusive = false;

    @Enumerated(EnumType.STRING)
    @Column(name = "promo_type", length = 30)
    private PromoType promoType;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    @Column(name = "is_visible", nullable = false)
    private Boolean isVisible = true;

    public void updateLocalImagePath(String path) {
        this.localImagePath = path;
        this.updatedAt = LocalDateTime.now();
    }

    public void updateEnScrydexRef(String enScrydexRef) {
        this.enScrydexRef = enScrydexRef;
        this.updatedAt = LocalDateTime.now();
    }

    public void updateJpScrydexRef(String jpScrydexRef) {
        this.jpScrydexRef = jpScrydexRef;
        this.updatedAt = LocalDateTime.now();
    }

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
