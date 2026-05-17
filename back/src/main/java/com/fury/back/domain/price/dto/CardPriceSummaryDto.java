package com.fury.back.domain.price.dto;

import java.util.List;

public record CardPriceSummaryDto(
        String cardId,
        KoPrice ko,
        Charts charts,
        PsaPrices enPsa,   // EN PSA 10/9 (USD), null if unavailable
        PsaPrices jpPsa    // JP PSA 10/9 (USD), null if unavailable
) {
    public record KoPrice(
            Integer mid,
            Integer low,
            Integer high,
            String basis,       // "NAVER_CAFE" or "FORMULA"
            String confidence,  // "A" / "B" / "C" / "D"
            int domesticCount,
            String asOfDate
    ) {}

    public record PsaPrices(
            Double psa10Usd,
            Double psa9Usd
    ) {}

    public record Charts(
            ChartData ko,
            ChartData en,
            ChartData jp
    ) {}

    public record ChartData(
            String chartType,  // "LINE", "POINTS", "NONE"
            String reason,     // "OK", "INSUFFICIENT_DATA", "FLAT_DATA"
            List<ChartPoint> line,
            List<ChartPoint> points,
            List<ChartPoint> psa10Line,
            List<ChartPoint> psa9Line
    ) {}

    public record ChartPoint(
            String date,
            Double price,
            Double rawPrice,
            String rawCurrency
    ) {}
}
