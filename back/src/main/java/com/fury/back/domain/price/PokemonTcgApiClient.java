package com.fury.back.domain.price;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * pokemontcg.io API 클라이언트
 * - 무료 API 키: https://dev.pokemontcg.io/ 에서 발급
 * - 키 없이도 1000 req/day 가능, 키 있으면 무제한
 */
@Slf4j
@Component
public class PokemonTcgApiClient {

    private static final String BASE_URL = "https://api.pokemontcg.io/v2";
    private static final List<String> PRICE_KEYS = List.of("holofoil", "normal", "reverseHolofoil", "1stEditionHolofoil");

    private final RestClient restClient;

    public PokemonTcgApiClient(@Value("${ptcg.api-key:}") String apiKey) {
        RestClient.Builder builder = RestClient.builder().baseUrl(BASE_URL);
        if (apiKey != null && !apiKey.isBlank()) {
            builder.defaultHeader("X-Api-Key", apiKey);
        }
        this.restClient = builder.build();
    }

    /**
     * 세트 ID + 카드 번호로 pokemontcg.io 카드 ID 검색
     *
     * @param ptcgSetId  pokemontcg.io 세트 ID (예: swsh12pt5)
     * @param cardNumber 카드 번호 (예: 244)
     * @return ptcg 카드 ID (예: swsh12pt5-244)
     */
    public Optional<String> findCardId(String ptcgSetId, String cardNumber) {
        try {
            String query = "number:" + cardNumber + " set.id:" + ptcgSetId;
            @SuppressWarnings("unchecked")
            Map<String, Object> response = restClient.get()
                    .uri(uriBuilder -> uriBuilder
                            .path("/cards")
                            .queryParam("q", query)
                            .queryParam("select", "id,number")
                            .build())
                    .retrieve()
                    .body(Map.class);

            if (response == null) return Optional.empty();

            @SuppressWarnings("unchecked")
            List<Map<String, Object>> data = (List<Map<String, Object>>) response.get("data");
            if (data == null || data.isEmpty()) return Optional.empty();

            String id = (String) data.get(0).get("id");
            return Optional.ofNullable(id);
        } catch (Exception e) {
            log.warn("PTCG API 카드 검색 실패: setId={}, number={}, error={}", ptcgSetId, cardNumber, e.getMessage());
            return Optional.empty();
        }
    }

    /**
     * pokemontcg.io 카드 ID로 TCGPlayer 시장가(USD) 조회
     *
     * @param ptcgCardId pokemontcg.io 카드 ID (예: swsh12pt5-244)
     * @return USD 시장가 (없으면 empty)
     */
    public Optional<Double> getMarketPriceUsd(String ptcgCardId) {
        try {
            @SuppressWarnings("unchecked")
            Map<String, Object> response = restClient.get()
                    .uri("/cards/" + ptcgCardId)
                    .retrieve()
                    .body(Map.class);

            if (response == null) return Optional.empty();

            @SuppressWarnings("unchecked")
            Map<String, Object> cardData = (Map<String, Object>) response.get("data");
            if (cardData == null) return Optional.empty();

            @SuppressWarnings("unchecked")
            Map<String, Object> tcgplayer = (Map<String, Object>) cardData.get("tcgplayer");
            if (tcgplayer == null) return Optional.empty();

            @SuppressWarnings("unchecked")
            Map<String, Map<String, Object>> prices = (Map<String, Map<String, Object>>) tcgplayer.get("prices");
            if (prices == null || prices.isEmpty()) return Optional.empty();

            // holofoil → normal → reverseHolofoil 순으로 market 가격 추출
            for (String key : PRICE_KEYS) {
                Map<String, Object> tier = prices.get(key);
                if (tier == null) continue;
                Object market = tier.get("market");
                if (market instanceof Number num && num.doubleValue() > 0) {
                    return Optional.of(num.doubleValue());
                }
            }
            return Optional.empty();
        } catch (Exception e) {
            log.warn("PTCG API 가격 조회 실패: cardId={}, error={}", ptcgCardId, e.getMessage());
            return Optional.empty();
        }
    }
}
