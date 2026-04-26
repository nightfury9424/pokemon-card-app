package com.fury.back.domain.price.dto;

import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

/**
 * 한국 시장 계수 DTO
 * coefficient = 한국 평균가 / 해외 환산가 평균
 * 예: 0.52 → 한국이 해외 대비 52% 수준 (48% 저렴)
 */
@Getter
@Builder
public class MarketCoefficientDto {
    private double coefficient;
    private int sampleSize;        // 계산에 사용된 카드 수
    private double exchangeRate;   // 계산 시 사용한 USD/KRW 환율
    private LocalDateTime calculatedAt;
}
