package com.fury.back.domain.price;

import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.Map;

/**
 * USD/KRW 환율 조회 (open.er-api.com - 무료, 인증 불필요)
 */
@Slf4j
@Component
public class ExchangeRateClient {

    private static final double FALLBACK_RATE = 1380.0;

    private final RestClient restClient;

    public ExchangeRateClient() {
        this.restClient = RestClient.builder()
                .baseUrl("https://open.er-api.com/v6")
                .build();
    }

    /**
     * 현재 USD → KRW 환율 반환
     * 실패 시 fallback으로 1380원 사용
     */
    public double getUsdToKrw() {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> response = restClient.get()
                    .uri("/latest/USD")
                    .retrieve()
                    .body(Map.class);

            if (response == null) return FALLBACK_RATE;

            @SuppressWarnings("unchecked")
            Map<String, Object> rates = (Map<String, Object>) response.get("rates");
            if (rates == null) return FALLBACK_RATE;

            Object krw = rates.get("KRW");
            if (krw instanceof Number num) {
                return num.doubleValue();
            }
            return FALLBACK_RATE;
        } catch (Exception e) {
            log.warn("환율 조회 실패, fallback 사용: {}", e.getMessage());
            return FALLBACK_RATE;
        }
    }
}
