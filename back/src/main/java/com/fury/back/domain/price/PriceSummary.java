package com.fury.back.domain.price;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "price_summaries")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PriceSummary {

    @Id
    @Column(name = "price_summary_id", length = 50)
    private String priceSummaryId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    // RAW / GRADED
    @Column(name = "card_status", nullable = false, length = 20)
    private String cardStatus;

    // PSA / BRG
    @Column(name = "grading_company", length = 20)
    private String gradingCompany;

    @Column(name = "grade_value", length = 20)
    private String gradeValue;

    // 7D / 30D
    @Column(name = "period", nullable = false, length = 10)
    private String period;

    @Column(name = "median_price")
    private Integer medianPrice;

    @Column(name = "avg_price")
    private Integer avgPrice;

    @Column(name = "min_price")
    private Integer minPrice;

    @Column(name = "max_price")
    private Integer maxPrice;

    @Column(name = "trade_count", nullable = false)
    private Integer tradeCount;

    @Column(name = "calculated_at", nullable = false)
    private LocalDateTime calculatedAt;
}
