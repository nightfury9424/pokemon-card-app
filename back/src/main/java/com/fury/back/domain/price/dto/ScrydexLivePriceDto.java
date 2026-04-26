package com.fury.back.domain.price.dto;

import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class ScrydexLivePriceDto {
    private Double rawNm;       // Raw Near Mint (USD)
    private Double psa10;       // PSA 10 최신 판매가 (USD)
    private Double psa9;        // PSA 9 최신 판매가 (USD)
    private String source;      // "JP" or "EN"
    private String ref;         // scrydex ref
}
