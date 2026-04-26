package com.fury.back.domain.asset.dto;

import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class PortfolioSummaryDto {

    private int totalCards;
    private int totalPurchasePrice;
    private long distinctCardCount;
}
