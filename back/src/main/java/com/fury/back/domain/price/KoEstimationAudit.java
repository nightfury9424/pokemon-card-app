package com.fury.back.domain.price;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.UUID;

/**
 * KO_ESTIMATED 산출 근거 + 랭킹 자격 audit.
 * docs/PRICE_POLICY_2026_05_16.md + 30+ 조건 통합 spec (2026-05-17).
 *
 * 매 KO_ESTIMATED row 생성 시 1:1로 함께 생성 (@Transactional 묶음).
 * 급상승/급하락 랭킹은 audit.ranking_eligible=true row만 후보.
 */
@Entity
@Table(name = "ko_estimation_audit")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class KoEstimationAudit {

    @Id
    @Column(name = "id", columnDefinition = "UUID")
    private UUID id;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    @Column(name = "ko_snapshot_id", nullable = false, length = 50)
    private String koSnapshotId;

    @Column(name = "estimated_date", nullable = false)
    private LocalDate estimatedDate;

    @Column(name = "ko_price", nullable = false)
    private Integer koPrice;

    // ─────────── Today selection ───────────
    @Column(name = "selected_source", length = 20)
    private String selectedSource;

    @Column(name = "selected_raw_snapshot_id", length = 50)
    private String selectedRawSnapshotId;

    @Column(name = "selected_raw_price_native", precision = 12, scale = 4)
    private BigDecimal selectedRawPriceNative;

    @Column(name = "selected_raw_currency", length = 3)
    private String selectedRawCurrency;

    @Column(name = "selected_raw_price_krw", precision = 14, scale = 2)
    private BigDecimal selectedRawPriceKrw;

    @Column(name = "selected_raw_traded_at")
    private LocalDateTime selectedRawTradedAt;

    @Column(name = "coef_scope", length = 20)
    private String coefScope;

    @Column(name = "coef_key", length = 100)
    private String coefKey;

    @Column(name = "coef_value", precision = 10, scale = 6)
    private BigDecimal coefValue;

    @Column(name = "usd_to_krw", precision = 10, scale = 4)
    private BigDecimal usdToKrw;

    @Column(name = "jpy_to_krw", precision = 10, scale = 4)
    private BigDecimal jpyToKrw;

    // ─────────── Prev selection ───────────
    @Column(name = "prev_ko_snapshot_id", length = 50)
    private String prevKoSnapshotId;

    @Column(name = "prev_selected_source", length = 20)
    private String prevSelectedSource;

    @Column(name = "prev_raw_snapshot_id", length = 50)
    private String prevRawSnapshotId;

    @Column(name = "prev_raw_price_native", precision = 12, scale = 4)
    private BigDecimal prevRawPriceNative;

    @Column(name = "prev_raw_currency", length = 3)
    private String prevRawCurrency;

    @Column(name = "prev_raw_price_krw", precision = 14, scale = 2)
    private BigDecimal prevRawPriceKrw;

    @Column(name = "prev_raw_traded_at")
    private LocalDateTime prevRawTradedAt;

    @Column(name = "prev_coef_scope", length = 20)
    private String prevCoefScope;

    @Column(name = "prev_coef_key", length = 100)
    private String prevCoefKey;

    @Column(name = "prev_coef_value", precision = 10, scale = 6)
    private BigDecimal prevCoefValue;

    @Column(name = "prev_usd_to_krw", precision = 10, scale = 4)
    private BigDecimal prevUsdToKrw;

    @Column(name = "prev_jpy_to_krw", precision = 10, scale = 4)
    private BigDecimal prevJpyToKrw;

    // ─────────── Change flags ───────────
    @Column(name = "raw_snapshot_changed", nullable = false)
    private boolean rawSnapshotChanged;

    @Column(name = "raw_time_changed", nullable = false)
    private boolean rawTimeChanged;

    /** native raw_price 기준 ≥0.5% 변동 (판정용) */
    @Column(name = "raw_changed", nullable = false)
    private boolean rawChanged;

    @Column(name = "raw_change_pct", precision = 12, scale = 4)
    private BigDecimal rawChangePct;

    @Column(name = "coef_changed", nullable = false)
    private boolean coefChanged;

    @Column(name = "exchange_rate_changed", nullable = false)
    private boolean exchangeRateChanged;

    /** 1차 구현에서는 항상 false. NAVER/DAANGN VALID 신규 반영 2차 phase에서 true 처리. */
    @Column(name = "has_ko_trade_change", nullable = false)
    private boolean hasKoTradeChange;

    // ─────────── Anomaly / Ranking ───────────
    @Column(name = "is_anomaly", nullable = false)
    private boolean anomaly;

    @Column(name = "anomaly_reason", length = 100)
    private String anomalyReason;

    @Column(name = "ranking_eligible", nullable = false)
    private boolean rankingEligible;

    @Column(name = "ranking_exclusion_reason", length = 100)
    private String rankingExclusionReason;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (id == null) id = UUID.randomUUID();
        if (createdAt == null) createdAt = LocalDateTime.now();
    }
}
