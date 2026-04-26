package com.fury.back.domain.price;

import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.price.dto.MarketCoefficientDto;
import com.fury.back.domain.price.dto.PriceSnapshotDto;
import com.fury.back.domain.price.dto.ScrydexHistoryDto;
import com.fury.back.domain.price.dto.ScrydexLivePriceDto;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class GlobalPriceService {

    private static final List<String> HIGH_RARE_CODES = List.of("SSR", "SAR", "BWR", "CSR", "CHR", "UR", "SR", "AR");
    private static final String SOURCE_TCGPLAYER = "TCGPLAYER";

    private final CardRepository cardRepository;
    private final PtcgSetMappingRepository ptcgSetMappingRepository;
    private final PriceSnapshotRepository priceSnapshotRepository;
    private final PokemonTcgApiClient pokemonTcgApiClient;
    private final ExchangeRateClient exchangeRateClient;
    private final ScrydexLiveClient scrydexLiveClient;

    // ─────────────────────────────────────────────
    // 1. 세트 매핑 저장 (productId → ptcgSetId)
    // ─────────────────────────────────────────────

    @Transactional
    public void saveSetMapping(String productId, String ptcgSetId) {
        PtcgSetMapping mapping = PtcgSetMapping.builder()
                .productId(productId)
                .ptcgSetId(ptcgSetId)
                .build();
        ptcgSetMappingRepository.save(mapping);
        log.info("세트 매핑 저장: productId={} → ptcgSetId={}", productId, ptcgSetId);
    }

    @Transactional
    public void saveSetMappings(Map<String, String> mappings) {
        mappings.forEach(this::saveSetMapping);
    }

    // ─────────────────────────────────────────────
    // 2. 카드 매핑 (KO 고레어 카드 → pokemontcg.io ID)
    // ─────────────────────────────────────────────

    @Transactional
    public Map<String, Object> mapCards() {
        List<PtcgSetMapping> setMappings = ptcgSetMappingRepository.findAll();
        if (setMappings.isEmpty()) {
            return Map.of("success", false, "message", "세트 매핑이 없습니다. 먼저 /set-mapping을 등록하세요.");
        }

        List<String> productIds = setMappings.stream().map(PtcgSetMapping::getProductId).toList();
        Map<String, String> productToSetId = setMappings.stream()
                .collect(Collectors.toMap(PtcgSetMapping::getProductId, PtcgSetMapping::getPtcgSetId));

        List<Card> unmappedCards = cardRepository.findByProductIdInAndRarityCodeInAndLanguage(
                productIds, HIGH_RARE_CODES, "KO");

        // 이미 매핑된 카드 제외
        unmappedCards = unmappedCards.stream()
                .filter(c -> c.getEnScrydexRef() == null)
                .toList();

        if (unmappedCards.isEmpty()) {
            return Map.of("success", true, "message", "매핑할 카드가 없습니다.", "mapped", 0);
        }

        log.info("카드 매핑 시작: {} 장", unmappedCards.size());
        int mapped = 0, failed = 0;

        for (Card card : unmappedCards) {
            String ptcgSetId = productToSetId.get(card.getProductId());
            if (ptcgSetId == null) continue;

            String cardNumber = extractCardNumber(card.getCollectionNumber());
            Optional<String> ptcgCardId = pokemonTcgApiClient.findCardId(ptcgSetId, cardNumber);

            if (ptcgCardId.isPresent()) {
                card.updateEnScrydexRef(ptcgCardId.get());
                cardRepository.save(card);
                mapped++;
                log.debug("매핑 성공: {} ({}) → {}", card.getName(), card.getCollectionNumber(), ptcgCardId.get());
            } else {
                failed++;
                log.debug("매핑 실패: {} ({})", card.getName(), card.getCollectionNumber());
            }

            // API rate limit 방지 (100ms 간격)
            sleep(100);
        }

        log.info("카드 매핑 완료: 성공={}, 실패={}", mapped, failed);
        return Map.of("success", true, "mapped", mapped, "failed", failed);
    }

    // ─────────────────────────────────────────────
    // 3. 해외 시세 수집 (매핑된 고레어 카드의 TCGPlayer USD 가격 → KRW 환산 저장)
    // ─────────────────────────────────────────────

    // pokemontcg.io 방식 비활성화 — scrydex 파이썬 배치로 대체 (JP+EN 통합, 히스토리+eBay 포함)
    @Transactional
    public Map<String, Object> fetchAndStorePrices() {
        return Map.of("success", false, "message", "Deprecated: scrydex 배치 스크립트(/tmp/scrydex_scraper.py)를 사용하세요.");
    }

    // ─────────────────────────────────────────────
    // 4. 한국 시장 계수 계산
    // ─────────────────────────────────────────────

    // 번호 체계가 한국/영어 동일하게 검증된 세트만 계수 계산에 사용
    // Black Bolt/White Flare는 SR+ 구간 번호가 달라 제외
    private static final List<String> VERIFIED_SET_IDS = List.of("sv3pt5");

    public MarketCoefficientDto getCoefficient() {
        // 검증된 세트의 매핑된 고레어 카드만 사용
        List<PtcgSetMapping> verifiedMappings = ptcgSetMappingRepository.findAll().stream()
                .filter(m -> VERIFIED_SET_IDS.contains(m.getPtcgSetId()))
                .toList();

        if (verifiedMappings.isEmpty()) {
            return MarketCoefficientDto.builder()
                    .coefficient(1.0).sampleSize(0)
                    .exchangeRate(exchangeRateClient.getUsdToKrw())
                    .calculatedAt(LocalDateTime.now()).build();
        }

        List<String> verifiedProductIds = verifiedMappings.stream()
                .map(PtcgSetMapping::getProductId).toList();

        List<Card> mappedCards = cardRepository
                .findByProductIdInAndRarityCodeInAndLanguage(verifiedProductIds, HIGH_RARE_CODES, "KO")
                .stream()
                .filter(c -> c.getEnScrydexRef() != null)
                .toList();

        if (mappedCards.isEmpty()) {
            return MarketCoefficientDto.builder()
                    .coefficient(1.0)
                    .sampleSize(0)
                    .exchangeRate(exchangeRateClient.getUsdToKrw())
                    .calculatedAt(LocalDateTime.now())
                    .build();
        }

        List<String> cardIds = mappedCards.stream().map(Card::getCardId).toList();
        // 한국: 앱의 "평균 거래가"와 동일하게 전체 기간 평균
        // 해외: 최근 30일 (오늘 수집한 TCGPlayer 가격)
        LocalDateTime krWindowStart = LocalDateTime.of(2000, 1, 1, 0, 0);
        LocalDateTime globalWindowStart = LocalDateTime.now().minusDays(30);

        List<PriceSnapshot> krSnapshots = priceSnapshotRepository.findKoreanPrices(cardIds, SOURCE_TCGPLAYER, krWindowStart);
        List<PriceSnapshot> globalSnapshots = priceSnapshotRepository.findGlobalPrices(cardIds, SOURCE_TCGPLAYER, globalWindowStart);

        // 카드별 평균가 계산
        Map<String, Double> krAvgByCard = krSnapshots.stream()
                .collect(Collectors.groupingBy(PriceSnapshot::getCardId,
                        Collectors.averagingInt(PriceSnapshot::getPrice)));

        Map<String, Double> globalAvgByCard = globalSnapshots.stream()
                .collect(Collectors.groupingBy(PriceSnapshot::getCardId,
                        Collectors.averagingInt(PriceSnapshot::getPrice)));

        // 양쪽 데이터가 모두 있는 카드만 계수 계산
        List<Double> ratios = new ArrayList<>();
        for (String cardId : cardIds) {
            Double krAvg = krAvgByCard.get(cardId);
            Double globalAvg = globalAvgByCard.get(cardId);
            if (krAvg != null && globalAvg != null && globalAvg > 0) {
                double ratio = krAvg / globalAvg;
                // 잘못된 매핑/데이터 이상치 제거 (0.01~5 범위만 신뢰)
                if (ratio >= 0.01 && ratio <= 5.0) {
                    ratios.add(ratio);
                }
            }
        }

        // 중앙값(median) 사용 - 이상치에 강건
        double coefficient = 1.0;
        if (!ratios.isEmpty()) {
            Collections.sort(ratios);
            int mid = ratios.size() / 2;
            coefficient = ratios.size() % 2 == 0
                    ? (ratios.get(mid - 1) + ratios.get(mid)) / 2.0
                    : ratios.get(mid);
        }

        double exchangeRate = exchangeRateClient.getUsdToKrw();
        return MarketCoefficientDto.builder()
                .coefficient(Math.round(coefficient * 1000.0) / 1000.0)
                .sampleSize(ratios.size())
                .exchangeRate(exchangeRate)
                .calculatedAt(LocalDateTime.now())
                .build();
    }

    // ─────────────────────────────────────────────
    // 5. 수동 카드 매핑 (card_id → tcgplayer_card_id)
    // ─────────────────────────────────────────────

    @Transactional
    public Map<String, Object> saveManualCardMappings(Map<String, String> mappings) {
        int updated = 0, notFound = 0;
        for (Map.Entry<String, String> entry : mappings.entrySet()) {
            Optional<Card> optCard = cardRepository.findById(entry.getKey());
            if (optCard.isPresent()) {
                optCard.get().updateEnScrydexRef(entry.getValue());
                cardRepository.save(optCard.get());
                updated++;
            } else {
                notFound++;
                log.warn("카드 없음: {}", entry.getKey());
            }
        }
        log.info("수동 매핑 완료: 업데이트={}, 없음={}", updated, notFound);
        return Map.of("updated", updated, "notFound", notFound);
    }

    @Transactional
    public Map<String, Object> clearCardMappings(List<String> cardIds) {
        int cleared = 0, notFound = 0;
        for (String cardId : cardIds) {
            Optional<Card> optCard = cardRepository.findById(cardId);
            if (optCard.isPresent()) {
                optCard.get().updateEnScrydexRef(null);
                cardRepository.save(optCard.get());
                cleared++;
            } else {
                notFound++;
                log.warn("카드 없음: {}", cardId);
            }
        }
        log.info("매핑 초기화 완료: cleared={}, notFound={}", cleared, notFound);
        return Map.of("cleared", cleared, "notFound", notFound);
    }

    public List<Map<String, Object>> getUnmappedHighRareCards(String productId) {
        List<Card> cards;
        if (productId != null && !productId.isBlank()) {
            cards = cardRepository.findByProductIdInAndRarityCodeInAndLanguage(
                    List.of(productId), HIGH_RARE_CODES, "KO").stream()
                    .filter(c -> c.getEnScrydexRef() == null)
                    .toList();
        } else {
            cards = cardRepository.findByRarityCodeInAndLanguageAndEnScrydexRefIsNull(
                    HIGH_RARE_CODES, "KO");
        }
        return cards.stream().map(c -> {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("cardId", c.getCardId());
            m.put("name", c.getName());
            m.put("rarity", c.getRarityCode());
            m.put("number", c.getCollectionNumber());
            m.put("productId", c.getProductId());
            return m;
        }).toList();
    }

    // ─────────────────────────────────────────────
    // 6. 특정 카드의 해외 시세 히스토리
    // ─────────────────────────────────────────────

    // ─────────────────────────────────────────────
    // 7. scrydex 실시간 가격 (RAW NM + PSA 9/10)
    // ─────────────────────────────────────────────

    public Optional<ScrydexHistoryDto> getScrydexHistory(String cardId, String source) {
        Card card = cardRepository.findById(cardId).orElse(null);
        if (card == null) return Optional.empty();

        if ("JP".equalsIgnoreCase(source)) {
            String jpRef = card.getJpScrydexRef();
            if (jpRef != null && !jpRef.isBlank() && !jpRef.startsWith("NO_")) {
                return scrydexLiveClient.fetchHistory(jpRef, "JP");
            }
        } else {
            String enRef = card.getEnScrydexRef();
            if (enRef != null && !enRef.isBlank() && !enRef.startsWith("NO_")) {
                return scrydexLiveClient.fetchHistory(enRef, "EN");
            }
        }
        return Optional.empty();
    }

    public Optional<ScrydexLivePriceDto> getScrydexLivePrice(String cardId) {
        Card card = cardRepository.findById(cardId).orElse(null);
        if (card == null) return Optional.empty();

        // EN ref 우선, 없으면 JP ref
        String enRef = card.getEnScrydexRef();
        String jpRef = card.getJpScrydexRef();

        if (enRef != null && !enRef.isBlank() && !enRef.startsWith("NO_")) {
            Optional<ScrydexLivePriceDto> result = scrydexLiveClient.fetchPrices(enRef, "EN");
            if (result.isPresent()) return result;
        }
        if (jpRef != null && !jpRef.isBlank() && !jpRef.startsWith("NO_")) {
            return scrydexLiveClient.fetchPrices(jpRef, "JP");
        }
        return Optional.empty();
    }

    public List<PriceSnapshotDto> getGlobalHistory(String cardId) {
        List<String> globalSources = List.of("SCRYDEX_JP", "SCRYDEX_EN", SOURCE_TCGPLAYER);
        return priceSnapshotRepository
                .findByCardIdAndSourceInAndCardStatusOrderByTradedAtDesc(cardId, globalSources, "RAW")
                .stream()
                .map(PriceSnapshotDto::from)
                .toList();
    }

    // ─────────────────────────────────────────────
    // Util
    // ─────────────────────────────────────────────

    /** collectionNumber에서 카드 번호 추출 (예: "244/184" → "244", "TG01/TG30" → "TG01") */
    private String extractCardNumber(String collectionNumber) {
        if (collectionNumber == null) return "";
        int slashIdx = collectionNumber.indexOf('/');
        return slashIdx > 0 ? collectionNumber.substring(0, slashIdx) : collectionNumber;
    }

    private void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }
}
