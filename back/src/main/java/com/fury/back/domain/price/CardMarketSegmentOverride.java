package com.fury.back.domain.price;

import jakarta.persistence.*;
import lombok.AccessLevel;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

/**
 * card_market_segment_overrides
 * Turn D-Round1 (2026-05-17) — card_id별 market_segment_key override.
 * resolveCoeffDetail priority chain: CARD > MARKET_SEGMENT > era_rarity > rarity > global.
 *
 * segment_source 추적값 (CHECK constraint):
 *   MANUAL / AUTO_ACCEPT / SUPPORTER_DETECTED / SUPPORTER_DETECTED_FROM_MANUAL / POKEMON_V_RESTORED
 */
@Entity
@Table(name = "card_market_segment_overrides")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
public class CardMarketSegmentOverride {

    @Id
    @Column(name = "card_id", length = 50)
    private String cardId;

    @Column(name = "market_segment_key", nullable = false, length = 80)
    private String marketSegmentKey;

    @Column(name = "segment_source", nullable = false, length = 50)
    private String segmentSource;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;
}
