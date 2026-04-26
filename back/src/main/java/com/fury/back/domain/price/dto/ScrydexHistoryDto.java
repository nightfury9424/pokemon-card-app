package com.fury.back.domain.price.dto;

import lombok.Builder;
import lombok.Getter;

import java.util.List;

@Getter
@Builder
public class ScrydexHistoryDto {

    private List<PricePoint> rawNm;
    private List<PricePoint> psa10;
    private List<PricePoint> psa9;
    private String source;
    private String ref;

    @Getter
    @Builder
    public static class PricePoint {
        private String date;
        private Double price;
    }
}
