package com.fury.back.domain.price.dto;

import com.fury.back.domain.price.PriceSummary;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class PriceSummaryDto {

    private String priceSummaryId;
    private String cardId;
    private String cardStatus;
    private String gradingCompany;
    private String gradeValue;
    private String period;
    private Integer medianPrice;
    private Integer avgPrice;
    private Integer minPrice;
    private Integer maxPrice;
    private Integer tradeCount;
    private LocalDateTime calculatedAt;

    public static PriceSummaryDto from(PriceSummary ps) {
        return PriceSummaryDto.builder()
                .priceSummaryId(ps.getPriceSummaryId())
                .cardId(ps.getCardId())
                .cardStatus(ps.getCardStatus())
                .gradingCompany(ps.getGradingCompany())
                .gradeValue(ps.getGradeValue())
                .period(ps.getPeriod())
                .medianPrice(ps.getMedianPrice())
                .avgPrice(ps.getAvgPrice())
                .minPrice(ps.getMinPrice())
                .maxPrice(ps.getMaxPrice())
                .tradeCount(ps.getTradeCount())
                .calculatedAt(ps.getCalculatedAt())
                .build();
    }
}
