package com.fury.back.domain.price;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Entity
@Table(name = "price_snapshots")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PriceSnapshot {

    @Id
    @Column(name = "price_snapshot_id", length = 50)
    private String priceSnapshotId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    // NAVER_CAFE / BUNJANG / SCRYDEX_EN / SCRYDEX_JP / KO_ESTIMATED
    @Column(name = "source", nullable = false, length = 20)
    private String source;

    @Column(name = "source_item_id", length = 100)
    private String sourceItemId;

    @Column(name = "source_url", length = 500)
    private String sourceUrl;

    @Column(name = "title", length = 500)
    private String title;

    @Column(name = "price", nullable = false)
    private Integer price;

    // 차트 표시용 가격 = price ± 랜덤 1~3% (KO 예상가 차트 생동감용). null이면 price 사용.
    // 대표가/범위는 price(진짜), 차트 선의 미세 흔들림만 chart_price. KO_ESTIMATED 행에만 채움.
    @Column(name = "chart_price")
    private Integer chartPrice;

    @Column(name = "raw_price")
    private BigDecimal rawPrice;

    @Column(name = "raw_currency", length = 3)
    private String rawCurrency;

    // RAW / GRADED
    @Column(name = "card_status", nullable = false, length = 20)
    private String cardStatus;

    // PSA / BRG
    @Column(name = "grading_company", length = 20)
    private String gradingCompany;

    // 10 / 9.5 ...
    @Column(name = "grade_value", length = 20)
    private String gradeValue;

    @Column(name = "cert_number", length = 100)
    private String certNumber;

    @Column(name = "traded_at", nullable = false)
    private LocalDateTime tradedAt;

    @Column(name = "collected_at", nullable = false)
    private LocalDateTime collectedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        this.createdAt = LocalDateTime.now();
    }

    /** 표시용 가격: chart_price(±3% 생동감값) 우선, 없으면 price.
     *  KO_ESTIMATED만 chart_price 보유(JP/EN/DAANGN 등은 null → price 그대로). 시세 내부로직은 계속 price(진짜) 사용. */
    public Integer getDisplayPrice() {
        return chartPrice != null ? chartPrice : price;
    }
}
