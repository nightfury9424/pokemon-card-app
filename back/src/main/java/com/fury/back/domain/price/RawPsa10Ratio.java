package com.fury.back.domain.price;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.IdClass;
import jakarta.persistence.Table;
import lombok.AccessLevel;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.EqualsAndHashCode;
import lombok.Getter;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * PSA10 가격에서 RAW 가격 추정용 비율. (source, rarity_code) 복합키.
 * PriceSyncScheduler에서 매일 갱신.
 */
@Entity
@Table(name = "raw_psa10_ratios")
@IdClass(RawPsa10Ratio.PK.class)
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class RawPsa10Ratio {

    @Id
    @Column(length = 20)
    private String source;

    @Id
    @Column(name = "rarity_code", length = 20)
    private String rarityCode;

    @Column(name = "window_days", nullable = false)
    private int windowDays;

    @Column(name = "sample_count", nullable = false)
    private int sampleCount;

    @Column(name = "ratio_median", nullable = false, precision = 8, scale = 5)
    private BigDecimal ratioMedian;

    @Column(name = "ratio_p25", precision = 8, scale = 5)
    private BigDecimal ratioP25;

    @Column(name = "ratio_p75", precision = 8, scale = 5)
    private BigDecimal ratioP75;

    @Column(name = "computed_at", nullable = false)
    private LocalDateTime computedAt;

    @EqualsAndHashCode
    @NoArgsConstructor
    @AllArgsConstructor
    public static class PK implements Serializable {
        private String source;
        private String rarityCode;
    }
}
