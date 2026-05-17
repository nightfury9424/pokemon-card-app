package com.fury.back.domain.price.dto;

import com.fury.back.domain.price.PriceSnapshot;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class PriceSnapshotDto {

    private String priceSnapshotId;
    private String cardId;
    private String source;
    private String sourceItemId;
    private String sourceUrl;
    private Integer price;
    private String cardStatus;
    private String gradingCompany;
    private String gradeValue;
    private String certNumber;
    private LocalDateTime tradedAt;
    private LocalDateTime collectedAt;

    public static PriceSnapshotDto from(PriceSnapshot ps) {
        return PriceSnapshotDto.builder()
                .priceSnapshotId(ps.getPriceSnapshotId())
                .cardId(ps.getCardId())
                .source(ps.getSource())
                .sourceItemId(ps.getSourceItemId())
                .sourceUrl(ps.getSourceUrl())
                .price(ps.getPrice())
                .cardStatus(ps.getCardStatus())
                .gradingCompany(ps.getGradingCompany())
                .gradeValue(ps.getGradeValue())
                .certNumber(ps.getCertNumber())
                .tradedAt(ps.getTradedAt())
                .collectedAt(ps.getCollectedAt())
                .build();
    }
}
