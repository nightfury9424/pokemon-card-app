package com.fury.back.domain.price;

import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.price.dto.CardPriceSummaryDto;
import com.fury.back.domain.price.dto.MarketCoefficientDto;
import com.fury.back.domain.price.dto.PriceSnapshotDto;
import com.fury.back.domain.price.dto.ScrydexHistoryDto;
import com.fury.back.domain.price.dto.ScrydexLivePriceDto;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
public class GlobalPriceService {

    private static final List<String> HIGH_RARE_CODES = List.of("SSR", "SAR", "BWR", "CSR", "CHR", "UR", "SR", "AR");
    private static final java.util.Set<String> HIGH_RARE_SET = new java.util.HashSet<>(List.of("SR","SAR","SSR","CSR","CHR","UR","HR","MUR","BWR"));
    private boolean isHighRare(String rarity) { return rarity != null && HIGH_RARE_SET.contains(rarity); }
    private static final String SOURCE_SCRYDEX_EN = "SCRYDEX_EN";
    // 카드 상세 차트의 표시 기간(일). source(SCRYDEX/KREAM/...)에 상관없이 모든 카드가 동일 window 사용.
    // 평탄선 합성도 이 값 기준 → 일반 카드/메타몽 같은 NO_EN/NO_JP 카드 시각적 일관성.
    private static final int CHART_WINDOW_DAYS = 14;
    private static final double JP_EN_RATIO_THRESHOLD = 8.0;
    // Phase 0+X hysteresis (2026-05-16) — source flip oscillation 차단.
    // prevSource 모름 → 기존 임계 2.0. prevSource=JP면 EN으로 flip 더 어렵게(2.2), EN이면 JP로 더 어렵게(1.8).
    // suspect-first 우선 (이상치 방어가 stickiness보다 강함).
    private static final double SPREAD_BASE = 2.0;
    private static final double SPREAD_TO_EN_FROM_JP = 2.2;
    private static final double SPREAD_TO_JP_FROM_EN = 1.8;
    private static final int JP_RAW_GLOBAL_CAP_KRW = 3_000_000;
    private static final Map<String, Integer> JP_RAW_RARITY_CAPS_KRW = Map.of(
            "HR", 2_000_000,
            "MUR", 2_000_000,
            "SR", 5_000_000,
            "SAR", 5_000_000,
            "SSR", 5_000_000
    );

    private final CardRepository cardRepository;
    private final PtcgSetMappingRepository ptcgSetMappingRepository;
    private final PriceSnapshotRepository priceSnapshotRepository;
    private final PokemonTcgApiClient pokemonTcgApiClient;
    private final CoefficientCache coefficientCache;
    private final ExchangeRateClient exchangeRateClient;
    private final RawPsa10RatioCalculator rawPsa10RatioCalculator;
    private final ScrydexLiveClient scrydexLiveClient;
    private final KoEstimationAuditRepository koAuditRepository;
    private final CardMarketSegmentOverrideRepository cardMarketSegmentOverrideRepository;

    /**
     * Turn D-Round1 (2026-05-17): card_id → market_segment_key map (batch fetch).
     * cardIds 비어있으면 empty map. per-card query 금지.
     */
    private Map<String, String> loadMarketSegmentOverrides(Set<String> cardIds) {
        if (cardIds == null || cardIds.isEmpty()) return Map.of();
        return cardMarketSegmentOverrideRepository.findByCardIdIn(cardIds).stream()
                .collect(Collectors.toMap(
                        CardMarketSegmentOverride::getCardId,
                        CardMarketSegmentOverride::getMarketSegmentKey,
                        (a, b) -> a));
    }

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
    // 3. 해외 시세 수집 (레거시 엔드포인트)
    // ─────────────────────────────────────────────

    // pokemontcg.io 방식 비활성화 — scrydex 파이썬 배치로 대체 (JP+EN 통합, 히스토리+eBay 포함)
    @Transactional
    public Map<String, Object> fetchAndStorePrices() {
        return Map.of("success", false, "message", "Deprecated: scrydex 배치 스크립트(/tmp/scrydex_scraper.py)를 사용하세요.");
    }

    // ─────────────────────────────────────────────
    // 4. 한국 시장 계수 계산
    // ─────────────────────────────────────────────

    /**
     * 캐시된 계수 반환. 캐시 없으면 즉석 계산 후 캐시에 저장.
     * 매일 스케줄러가 갱신하므로 정상 운영 시 항상 캐시 히트.
     */
    @org.springframework.transaction.annotation.Transactional
    public MarketCoefficientDto getCoefficient() {
        MarketCoefficientDto cached = coefficientCache.getOrNull();
        if (cached != null) return cached;
        // 캐시 미스 (서버 재시작 직후 등) → 즉석 계산 후 캐시 저장
        MarketCoefficientDto fresh = recalculateCoefficient();
        coefficientCache.update(fresh);
        return fresh;
    }

    /**
     * 계수를 새로 계산하고 캐시 업데이트.
     * 스케줄러 or 수동 트리거 시 호출.
     */
    public MarketCoefficientDto recalculateCoefficient() {
        log.info("[Coefficient] 계산 시작");

        // EN 또는 JP scrydex 매핑된 고레어 KO 카드 전체 (JP 전용 카드 포함)
        List<Card> mappedCards = cardRepository
                .findByRarityCodeInAndLanguage(HIGH_RARE_CODES, "KO")
                .stream()
                .filter(c -> (c.getEnScrydexRef() != null && !c.getEnScrydexRef().startsWith("NO_"))
                          || (c.getJpScrydexRef() != null && !c.getJpScrydexRef().startsWith("NO_")))
                .toList();

        double exchangeRate = exchangeRateClient.getUsdToKrw();
        double jpyExchangeRate = exchangeRateClient.getJpyToKrw();

        if (mappedCards.isEmpty()) {
            log.warn("[Coefficient] 매핑된 카드 없음 → coefficient=1.0");
            return MarketCoefficientDto.builder()
                    .coefficient(1.0).sampleSize(0)
                    .exchangeRate(exchangeRate)
                    .calculatedAt(LocalDateTime.now()).build();
        }

        List<String> cardIds = mappedCards.stream().map(Card::getCardId).toList();

        // 한국 시세: NAVER_CAFE/BUNJANG RAW 최근 60일만 계수 계산에 사용
        LocalDateTime krWindowStart = LocalDateTime.now().minusDays(60);
        List<PriceSnapshot> krSnapshots = priceSnapshotRepository
                .findKoreanPrices(cardIds, krWindowStart);

        // 해외 시세: SCRYDEX_JP 우선, 없으면 SCRYDEX_EN (원본가가 있으면 최신 환율로 KRW 환산)
        LocalDateTime globalWindowStart = LocalDateTime.now().minusDays(60);
        Map<String, Double> enAvgByCard = priceSnapshotRepository
                .findGlobalPrices(cardIds, SOURCE_SCRYDEX_EN, globalWindowStart).stream()
                .collect(Collectors.groupingBy(PriceSnapshot::getCardId,
                        Collectors.averagingDouble(s -> toLatestKrw(s, exchangeRate, jpyExchangeRate))));
        Map<String, Double> jpAvgByCard = priceSnapshotRepository
                .findGlobalPrices(cardIds, "SCRYDEX_JP", globalWindowStart).stream()
                .collect(Collectors.groupingBy(PriceSnapshot::getCardId,
                        Collectors.averagingDouble(s -> toLatestKrw(s, exchangeRate, jpyExchangeRate))));

        Map<String, Double> krAvgByCard = krSnapshots.stream()
                .collect(Collectors.groupingBy(PriceSnapshot::getCardId,
                        Collectors.averagingInt(PriceSnapshot::getPrice)));

        List<Double> ratios = new ArrayList<>();
        for (String cardId : cardIds) {
            Double krAvg = krAvgByCard.get(cardId);
            if (krAvg == null) continue;
            // JP 우선, 없으면 EN
            Double globalAvg = jpAvgByCard.containsKey(cardId)
                    ? jpAvgByCard.get(cardId)
                    : enAvgByCard.get(cardId);
            if (globalAvg == null || globalAvg <= 0) continue;
            double ratio = krAvg / globalAvg;
            // 이상치 제거: 0.05 ~ 3.0 범위만 신뢰
            if (ratio >= 0.05 && ratio <= 3.0) ratios.add(ratio);
        }

        // 중앙값(median) 사용 — 이상치에 강건
        double coefficient = 1.0;
        if (!ratios.isEmpty()) {
            Collections.sort(ratios);
            int mid = ratios.size() / 2;
            coefficient = ratios.size() % 2 == 0
                    ? (ratios.get(mid - 1) + ratios.get(mid)) / 2.0
                    : ratios.get(mid);
        }

        double finalCoeff = Math.round(coefficient * 1000.0) / 1000.0;
        LocalDateTime now = LocalDateTime.now();

        log.info("[Coefficient] 완료: coefficient={}, sample={}, usdRate={}, jpyRate={}",
                finalCoeff, ratios.size(), exchangeRate, jpyExchangeRate);

        // 히스토리 저장 (price = coefficient × 10000, currency = 'RATIO')
        saveHistoryEntry(finalCoeff, now);

        // KO_ESTIMATED 저장은 23:45 refreshKoEstimatesFromSnapshots()로 일원화.
        // 23:15 시점엔 글로벌 계수만 갱신하고 KO 스냅샷은 만들지 않음 — 중복 갱신 + 부정확한 통화 혼합 ratio 방지.
        // REFACTOR_2026-05-12.md 2-② 참조.

        return MarketCoefficientDto.builder()
                .coefficient(finalCoeff)
                .sampleSize(ratios.size())
                .exchangeRate(exchangeRate)
                .calculatedAt(now)
                .build();
    }

    private static final String COEFF_CARD_ID = "ko_market_coefficient";
    private static final String COEFF_SOURCE  = "SYSTEM";

    @Transactional
    public void saveHistoryEntry(double coefficient, LocalDateTime at) {
        // 하루 1번만 저장 (당일 이미 있으면 스킵)
        boolean exists = priceSnapshotRepository
                .existsByCardIdAndSourceAndTradedAtAfter(COEFF_CARD_ID, COEFF_SOURCE, at.toLocalDate().atStartOfDay());
        if (exists) return;

        PriceSnapshot entry = PriceSnapshot.builder()
                .priceSnapshotId(com.fury.back.common.IdGenerator.generate())
                .cardId(COEFF_CARD_ID)
                .source(COEFF_SOURCE)
                .price((int) Math.round(coefficient * 10000))
                .cardStatus("RAW")
                .tradedAt(at)
                .collectedAt(at)
                .build();
        priceSnapshotRepository.save(entry);
    }

    /** 레어도별 계수 맵 로드: jp_{rarity}/en_{rarity} → coefficient */
    private Map<String, Double> loadRarityCoefficients() {
        return priceSnapshotRepository.findAllRarityCoefficients().stream()
                .collect(Collectors.toMap(
                        s -> s.getCardId().replace("ko_coef_", ""),
                        s -> s.getPrice() / 10000.0
                ));
    }

    /**
     * ko_price_coefficients의 활성 CARD coef를 로드.
     * Map<cardId, Map<coef_type, coef>> 형태. coef_type: JP / EN / BLEND.
     * 카드별 outlier 보정용 — 실거래 직접 fit이라 ×1.12 미적용 (raw 그대로).
     */
    private Map<String, Map<String, Double>> loadCardCoefficients() {
        Map<String, Map<String, Double>> result = new HashMap<>();
        for (Object[] row : priceSnapshotRepository.findActiveCardCoefficients()) {
            String cardId = (String) row[0];
            String coefType = (String) row[1];
            Double coef = ((Number) row[2]).doubleValue();
            result.computeIfAbsent(cardId, k -> new HashMap<>()).put(coefType, coef);
        }
        return result;
    }

    private double coefficientForSource(
            Map<String, Double> coeffs,
            String source,
            String rarity,
            double globalCoefficient) {
        return resolveCoeff(coeffs, source, "UNKNOWN", rarity, globalCoefficient);
    }

    /**
     * PSA10 가격 → 추정 외국 RAW(× ratio) → 한국 시세(× rarity 계수). 2단계 환산.
     * KO 발매 카드 + rarity 있을 때만. ratio 없거나 계수 없으면 Optional.empty.
     */
    public Optional<Integer> derivedKoFromJpPsa10(Card card, int jpPsa10Krw) {
        if (card == null) return Optional.empty();
        if (!"KO".equalsIgnoreCase(card.getLanguage())) return Optional.empty();
        String rarity = card.getRarityCode();
        if (rarity == null || rarity.isBlank()) return Optional.empty();
        // 1단계: PSA10 → 추정 외국 RAW (KRW 환산)
        Optional<Integer> derivedRaw = rawPsa10RatioCalculator
                .deriveRawFromPsa10("SCRYDEX_JP", rarity, jpPsa10Krw);
        if (derivedRaw.isEmpty()) return Optional.empty();
        // 2단계: 외국 RAW × rarity 계수 = 한국 시세
        Map<String, Double> rarityCoeffs = loadRarityCoefficients();
        double globalCoeff = getCoefficient().getCoefficient();
        double globalJpFallback = rarityCoeffs.getOrDefault("jp_GLOBAL", globalCoeff);
        String era = resolveEraFromCard(card);
        double coeff = applyEraCap("SCRYDEX_JP", era, rarity,
                resolveCoeff(rarityCoeffs, "SCRYDEX_JP", era, rarity, globalJpFallback));
        int koPrice = (int) Math.round(derivedRaw.get() * coeff);
        return koPrice > 0 ? Optional.of(koPrice) : Optional.empty();
    }

    public String resolveEra(String officialCardCode) {
        if (officialCardCode == null || officialCardCode.isBlank()
                || !officialCardCode.startsWith("BS") || officialCardCode.length() < 6) {
            return "UNKNOWN";
        }

        try {
            int year = Integer.parseInt(officialCardCode.substring(2, 6));
            if (year >= 2010 && year <= 2013) return "BW";
            if (year >= 2014 && year <= 2016) return "XY";
            if (year >= 2017 && year <= 2019) return "SM";
            if (year >= 2020 && year <= 2022) return "SWSH";
            if (year >= 2023 && year <= 2026) return "SV";
            return "UNKNOWN";
        } catch (NumberFormatException e) {
            return "UNKNOWN";
        }
    }

    // DC1 (Double Crisis EN) / CP1 (JP) 세트는 영문판 한정 수집가 시장 가격이 형성되어
    // 한국 거래 가격과 큰 괴리가 있어 별도 계수(en_DC1_*)로 처리
    public String resolveEraFromCard(Card card) {
        if (card == null) return "UNKNOWN";
        String enRef = card.getEnScrydexRef();
        if (enRef != null && enRef.startsWith("dc1-")) return "DC1";
        return resolveEra(card.getOfficialCardCode());
    }

    public double resolveCoeff(
            Map<String, Double> coeffs,
            String source,
            String era,
            String rarity,
            double globalFallback) {
        if (coeffs == null || coeffs.isEmpty()) return globalFallback;
        String sourceKey;
        if ("SCRYDEX_EN".equals(source)) {
            sourceKey = "en";
        } else if ("SCRYDEX_JP".equals(source)) {
            sourceKey = "jp";
        } else {
            sourceKey = source == null ? "" : source.toLowerCase(Locale.ROOT);
        }
        String rarityKey = rarity == null ? "" : rarity;
        String eraKey = era == null || era.isBlank() ? "UNKNOWN" : era;
        return coeffs.getOrDefault(sourceKey + "_" + eraKey + "_" + rarityKey,
                coeffs.getOrDefault(sourceKey + "_" + rarityKey, globalFallback));
    }

    /**
     * resolveCoeff와 동일 로직 + 어느 layer(scope/key)에서 왔는지 같이 반환.
     * audit의 coef_scope/coef_key/coef_value 정확 기록용 (Step B-3.5).
     *
     * scope: RARITY (era_rarity 또는 rarity 매칭) / GLOBAL (fallback)
     * key: 실제 lookup된 key 그대로 (ko_coef_* 접두는 storage prefix이므로 음역 X — lookup map의 key 그대로 저장)
     * value: raw resolved (applyEraCap 미적용, 외부에서 cap 적용 후 새 CoefResolution 만들어야 함)
     */
    private CoefResolution resolveCoeffDetail(
            Map<String, Double> coeffs,
            String source,
            String era,
            String rarity,
            String marketSegmentKey,
            double globalFallback,
            String globalFallbackKey) {
        if (coeffs == null || coeffs.isEmpty()) {
            return new CoefResolution("GLOBAL", globalFallbackKey, BigDecimal.valueOf(globalFallback));
        }
        String sourceKey;
        if ("SCRYDEX_EN".equals(source)) sourceKey = "en";
        else if ("SCRYDEX_JP".equals(source)) sourceKey = "jp";
        else sourceKey = source == null ? "" : source.toLowerCase(Locale.ROOT);
        String rarityKey = rarity == null ? "" : rarity;
        String eraKey = era == null || era.isBlank() ? "UNKNOWN" : era;

        // Turn D-Round1 (2026-05-17): 0순위 MARKET_SEGMENT
        // segmentKey 있고 해당 coef 저장돼 있으면 우선. 없으면 기존 fallback으로 안전하게 내려감.
        if (marketSegmentKey != null && !marketSegmentKey.isBlank()) {
            String segKey = sourceKey + "_" + marketSegmentKey;
            if (coeffs.containsKey(segKey)) {
                return new CoefResolution("MARKET_SEGMENT", segKey, BigDecimal.valueOf(coeffs.get(segKey)));
            }
        }
        // 1순위: era_rarity
        String tryKey1 = sourceKey + "_" + eraKey + "_" + rarityKey;
        if (coeffs.containsKey(tryKey1)) {
            return new CoefResolution("RARITY", tryKey1, BigDecimal.valueOf(coeffs.get(tryKey1)));
        }
        // 2순위: rarity
        String tryKey2 = sourceKey + "_" + rarityKey;
        if (coeffs.containsKey(tryKey2)) {
            return new CoefResolution("RARITY", tryKey2, BigDecimal.valueOf(coeffs.get(tryKey2)));
        }
        // 3순위: globalFallback
        return new CoefResolution("GLOBAL", globalFallbackKey, BigDecimal.valueOf(globalFallback));
    }

    /**
     * KO_ESTIMATED 산출 시 어떤 계수가 사용됐는지 audit 메타.
     * scope: CARD / RARITY / GLOBAL / NONE (PROMO_DIRECT/PSA10_FALLBACK은 coef 없음)
     * key: 실제 lookup key 또는 CARD:{cardId}:{JP|EN}
     * value: 최종 KO 계산에 사용된 coefficient (applyEraCap 적용 후)
     */
    public record CoefResolution(String scope, String key, BigDecimal value) {}

    public double applyEraCap(String source, String era, String rarity, double coeff) {
        if (!SOURCE_SCRYDEX_EN.equals(source) || !"SR".equals(rarity)) {
            return coeff;
        }
        return switch (era) {
            case "BW" -> Math.min(coeff, 0.10);
            case "XY" -> Math.min(coeff, 0.15);
            default -> coeff;
        };
    }

    /** SCRYDEX 가격 × 레어도별 계수 → KO_ESTIMATED 배치 저장 */
    @Transactional
    public void saveKoEstimatedSnapshots(double globalCoefficient, LocalDateTime at) {
        double usdToKrw = exchangeRateClient.getUsdToKrw();
        double jpyToKrw = exchangeRateClient.getJpyToKrw();
        List<PriceSnapshot> enSnapshots = priceSnapshotRepository.findAllLatestScrydexEn();
        List<PriceSnapshot> jpSnapshots = priceSnapshotRepository.findAllLatestScrydexJp();

        Map<String, PriceSnapshot> enMap = enSnapshots.stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));
        Map<String, PriceSnapshot> jpMap = jpSnapshots.stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));

        Set<String> allIds = new java.util.HashSet<>(enMap.keySet());
        allIds.addAll(jpMap.keySet());
        if (allIds.isEmpty()) { log.warn("[KoEstimated] 스냅샷 없음, 스킵"); return; }

        // hysteresis prevSource — 어제 KO_ESTIMATED 기준 추정 (daily run)
        Map<String, Double> rarityCoeffsForInfer = loadRarityCoefficients();
        Map<String, Map<String, Double>> cardCoefsForInfer = loadCardCoefficients();
        Map<String, String> prevSourceMap = inferPrevKoSources(
                LocalDate.now().minusDays(1), allIds, rarityCoeffsForInfer, cardCoefsForInfer, usdToKrw, jpyToKrw);
        BuildKoResult buildResult = buildKoEstimatedSnapshots(
                allIds, enMap, jpMap, globalCoefficient, usdToKrw, jpyToKrw, at, prevSourceMap);
        List<PriceSnapshot> koSnapshots = buildResult.snapshots();
        if (koSnapshots.isEmpty()) { log.warn("[KoEstimated] 생성 가능한 KO 예상가 없음, 스킵"); return; }
        // 오늘자 KO_ESTIMATED만 삭제 후 재삽입 (과거 히스토리 보존)
        List<String> cardIdList = koSnapshots.stream().map(PriceSnapshot::getCardId).toList();
        priceSnapshotRepository.deleteTodayKoEstimated(cardIdList);
        priceSnapshotRepository.saveAll(koSnapshots);
        log.info("[KoEstimated] {}장 KO 예상가 저장 완료 (최신 환율/레어도별 계수 적용)", koSnapshots.size());
    }

    @Transactional
    public Map<String, Object> backfillKoEstimatedHistory(int days, boolean force) {
        int normalizedDays = Math.max(1, days);
        double globalCoefficient = getLatestCoefficientValue();
        double usdToKrw = exchangeRateClient.getUsdToKrw();
        double jpyToKrw = exchangeRateClient.getJpyToKrw();

        int saved = 0;
        int savedAudits = 0;
        int skippedExisting = 0;
        int deletedExisting = 0;
        int daysProcessed = 0;
        LocalDate today = LocalDate.now();
        // Phase 0+X hysteresis (2026-05-16): ASC 순회 + carry
        // Turn C-2 (2026-05-17): audit carry 추가. force=true 시 기존 KO_ESTIMATED 14일치 삭제 후 재생성.
        // 첫 날짜만 legacy inferPrevKoSources fallback + DB audit override. 그 다음부터는 in-memory carry.
        Map<String, Double> rarityCoeffsForInfer = loadRarityCoefficients();
        Map<String, Map<String, Double>> cardCoefsForInfer = loadCardCoefficients();
        Map<String, String> carrySourceMap = new HashMap<>();
        Map<String, KoEstimationAudit> carryAuditMap = new HashMap<>();
        boolean firstIteration = true;
        for (int offset = normalizedDays; offset >= 1; offset--) {
            LocalDate date = today.minusDays(offset);
            LocalDateTime start = date.atStartOfDay();
            LocalDateTime end = date.plusDays(1).atStartOfDay();
            LocalDateTime backfillAt = date.atTime(2, 0);

            Set<String> existingKoIds = priceSnapshotRepository
                    .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("KO_ESTIMATED", start, end)
                    .stream()
                    .map(PriceSnapshot::getCardId)
                    .collect(Collectors.toSet());

            // Staleness 30d
            LocalDateTime stalenessStart = start.minusDays(30);
            Map<String, PriceSnapshot> enMap = priceSnapshotRepository
                    .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("SCRYDEX_EN", stalenessStart, end)
                    .stream()
                    .filter(s -> "RAW".equals(s.getCardStatus()))
                    .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> b));
            Map<String, PriceSnapshot> jpMap = priceSnapshotRepository
                    .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("SCRYDEX_JP", stalenessStart, end)
                    .stream()
                    .filter(s -> "RAW".equals(s.getCardStatus()))
                    .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> b));

            Set<String> allIds = new HashSet<>(enMap.keySet());
            allIds.addAll(jpMap.keySet());
            int candidateCount = allIds.size();
            if (!force) {
                allIds.removeAll(existingKoIds);
                skippedExisting += candidateCount - allIds.size();
            } else if (!existingKoIds.isEmpty()) {
                // force=true: 기존 KO_ESTIMATED 일괄 삭제 (FK CASCADE로 audit도 함께 삭제)
                priceSnapshotRepository.deleteKoEstimatedByDateRange(
                        new ArrayList<>(existingKoIds), start, end);
                priceSnapshotRepository.flush();
                deletedExisting += existingKoIds.size();
            }
            if (allIds.isEmpty()) {
                daysProcessed++;
                continue;
            }

            // 첫 iteration: legacy inferPrevKoSources fallback + DB audit override
            Map<String, String> prevSourceMap;
            Map<String, KoEstimationAudit> prevAuditMap;
            if (firstIteration) {
                Map<String, String> legacyPrev = inferPrevKoSources(date.minusDays(1), allIds,
                        rarityCoeffsForInfer, cardCoefsForInfer, usdToKrw, jpyToKrw);
                prevAuditMap = inferPrevAudits(date.minusDays(1), allIds);
                Map<String, String> auditPrev = prevAuditMap.entrySet().stream()
                        .collect(Collectors.toMap(Map.Entry::getKey, e -> e.getValue().getSelectedSource()));
                prevSourceMap = new HashMap<>(legacyPrev);
                prevSourceMap.putAll(auditPrev);
                firstIteration = false;
            } else {
                prevSourceMap = carrySourceMap;
                prevAuditMap = carryAuditMap;
            }

            BuildKoResult result = buildKoEstimatedSnapshotsWithAudit(
                    allIds, enMap, jpMap, globalCoefficient, usdToKrw, jpyToKrw, backfillAt,
                    prevSourceMap, prevAuditMap);

            // 1:1 보장 검증 — mismatch 시 rollback (backfill은 KREAM promo 경로 없음)
            if (result.snapshots().size() != result.audits().size()) {
                throw new IllegalStateException(String.format(
                        "[KoEstimatedBackfill] count mismatch date=%s snapshots=%d audits=%d",
                        date, result.snapshots().size(), result.audits().size()));
            }

            priceSnapshotRepository.saveAll(result.snapshots());
            priceSnapshotRepository.flush(); // FK constraint 위해 audit insert 전 snapshot row 확정
            koAuditRepository.saveAll(result.audits());
            saved += result.snapshots().size();
            savedAudits += result.audits().size();
            daysProcessed++;

            // carry — 다음 iteration의 prevSource/prevAudit
            carrySourceMap = result.selectedSourceByCard();
            carryAuditMap = result.audits().stream()
                    .collect(Collectors.toMap(KoEstimationAudit::getCardId, a -> a, (a, b) -> b));
        }

        log.info("[KoEstimatedBackfill] 완료: days={}, saved={}, audits={}, skippedExisting={}, deletedExisting={}, force={}",
                normalizedDays, saved, savedAudits, skippedExisting, deletedExisting, force);
        return Map.of(
                "status", "backfilled",
                "days", daysProcessed,
                "saved", saved,
                "savedAudits", savedAudits,
                "skippedExisting", skippedExisting,
                "deletedExisting", deletedExisting,
                "force", force);
    }

    /**
     * Step B-5 / Option D — DB write 없는 in-memory carry dry-run.
     *
     * 목적: buildKoEstimatedSnapshotsWithAudit를 N일치 (max 14) 연속으로 carry 돌려서
     * audit 판정 (raw_changed / coef_changed / source_changed / ranking_exclusion_reason)이
     * 의도대로 나오는지 검증. price_snapshots/ko_estimation_audit 둘 다 저장하지 않음.
     *
     * 환율은 latest 3일 동일 사용 (exchange_rate_changed=false 고정).
     * 환율 히스토리 검증은 별도 단계.
     *
     * 제한:
     * - cardIds.size() ≤ 50
     * - days ≤ 14
     */
    public Map<String, Object> dryRunAuditNDays(
            List<String> cardIds, LocalDate startDate, LocalDate endDate) {
        if (cardIds == null || cardIds.isEmpty()) {
            return Map.of("error", "cardIds required");
        }
        if (cardIds.size() > 50) {
            return Map.of("error", "cardIds max 50, got " + cardIds.size());
        }
        if (startDate == null || endDate == null || endDate.isBefore(startDate)) {
            return Map.of("error", "invalid date range");
        }
        long days = ChronoUnit.DAYS.between(startDate, endDate) + 1;
        if (days > 14) {
            return Map.of("error", "max 14 days, got " + days);
        }

        double usdToKrw = exchangeRateClient.getUsdToKrw();
        double jpyToKrw = exchangeRateClient.getJpyToKrw();
        double globalCoefficient = getLatestCoefficientValue();

        Set<String> cardIdSet = new HashSet<>(cardIds);
        Map<String, Card> cardMap = cardRepository.findAllById(cardIdSet).stream()
                .collect(Collectors.toMap(Card::getCardId, c -> c, (a, b) -> a));

        Map<String, String> carrySourceMap = Map.of();
        Map<String, KoEstimationAudit> carryAuditMap = Map.of();

        List<Map<String, Object>> auditRows = new ArrayList<>();
        int totalSnapshots = 0;
        int totalAudits = 0;

        LocalDate date = startDate;
        while (!date.isAfter(endDate)) {
            LocalDateTime start = date.atStartOfDay();
            LocalDateTime end = date.plusDays(1).atStartOfDay();
            LocalDateTime at = date.atTime(2, 0);
            LocalDateTime stalenessStart = start.minusDays(30);

            Map<String, PriceSnapshot> enMap = priceSnapshotRepository
                    .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("SCRYDEX_EN", stalenessStart, end)
                    .stream()
                    .filter(s -> "RAW".equals(s.getCardStatus()))
                    .filter(s -> cardIdSet.contains(s.getCardId()))
                    .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> b));
            Map<String, PriceSnapshot> jpMap = priceSnapshotRepository
                    .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("SCRYDEX_JP", stalenessStart, end)
                    .stream()
                    .filter(s -> "RAW".equals(s.getCardStatus()))
                    .filter(s -> cardIdSet.contains(s.getCardId()))
                    .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> b));

            // DRY-RUN: saveAll 절대 호출 금지
            BuildKoResult result = buildKoEstimatedSnapshotsWithAudit(
                    cardIdSet, enMap, jpMap, globalCoefficient,
                    usdToKrw, jpyToKrw, at, carrySourceMap, carryAuditMap);

            totalSnapshots += result.snapshots().size();
            totalAudits += result.audits().size();

            LocalDate currentDate = date;
            for (KoEstimationAudit audit : result.audits()) {
                Card card = cardMap.get(audit.getCardId());
                Map<String, Object> row = new LinkedHashMap<>();
                row.put("date", currentDate.toString());
                row.put("card_id", audit.getCardId());
                row.put("name", card != null ? card.getName() : null);
                row.put("ko_price", audit.getKoPrice());
                row.put("selected_source", audit.getSelectedSource());
                row.put("prev_selected_source", audit.getPrevSelectedSource());
                row.put("selected_raw_price_native", audit.getSelectedRawPriceNative());
                row.put("prev_raw_price_native", audit.getPrevRawPriceNative());
                row.put("raw_change_pct", audit.getRawChangePct());
                row.put("raw_changed", audit.isRawChanged());
                row.put("coef_scope", audit.getCoefScope());
                row.put("coef_key", audit.getCoefKey());
                row.put("coef_value", audit.getCoefValue());
                row.put("prev_coef_scope", audit.getPrevCoefScope());
                row.put("prev_coef_key", audit.getPrevCoefKey());
                row.put("prev_coef_value", audit.getPrevCoefValue());
                row.put("coef_changed", audit.isCoefChanged());
                row.put("exchange_rate_changed", audit.isExchangeRateChanged());
                row.put("is_anomaly", audit.isAnomaly());
                row.put("anomaly_reason", audit.getAnomalyReason());
                row.put("ranking_eligible", audit.isRankingEligible());
                row.put("ranking_exclusion_reason", audit.getRankingExclusionReason());
                auditRows.add(row);
            }

            // carry update — 다음 날짜 prevAuditMap/prevSourceMap으로
            carrySourceMap = result.selectedSourceByCard();
            carryAuditMap = result.audits().stream()
                    .collect(Collectors.toMap(KoEstimationAudit::getCardId, a -> a, (a, b) -> b));

            date = date.plusDays(1);
        }

        log.info("[DryRunAudit] cards={} startDate={} endDate={} totalSnapshots={} totalAudits={}",
                cardIds.size(), startDate, endDate, totalSnapshots, totalAudits);

        Map<String, Object> response = new LinkedHashMap<>();
        response.put("status", "dry-run");
        response.put("startDate", startDate.toString());
        response.put("endDate", endDate.toString());
        response.put("cardCount", cardIds.size());
        response.put("usdToKrw", usdToKrw);
        response.put("jpyToKrw", jpyToKrw);
        response.put("globalCoefficient", globalCoefficient);
        response.put("totalSnapshots", totalSnapshots);
        response.put("totalAudits", totalAudits);
        response.put("rows", auditRows);
        return response;
    }

    private double getLatestCoefficientValue() {
        MarketCoefficientDto cached = coefficientCache.getOrNull();
        if (cached != null) return cached.getCoefficient();
        List<PriceSnapshot> history = priceSnapshotRepository
                .findByCardIdAndSourceOrderByTradedAtAsc(COEFF_CARD_ID, COEFF_SOURCE);
        if (history.isEmpty()) return 1.0;
        return history.get(history.size() - 1).getPrice() / 10000.0;
    }

    /**
     * Step B-4b: buildKoEstimatedSnapshotsWithAudit 호출 wrapper.
     *
     * 기존 시그니처/반환 타입 유지 — 호출자 3곳(saveKoEstimatedSnapshots, backfillKoEstimatedHistory,
     * refreshKoEstimatesFromSnapshots) 변경 없음. audit 생성은 비활성(Map.of() 전달).
     *
     * Turn C에서 audit 저장이 필요한 caller는 buildKoEstimatedSnapshotsWithAudit를
     * inferPrevAudits 결과와 함께 직접 호출해야 함.
     */
    private BuildKoResult buildKoEstimatedSnapshots(
            Set<String> cardIds,
            Map<String, PriceSnapshot> enMap,
            Map<String, PriceSnapshot> jpMap,
            double globalCoefficient,
            double usdToKrw,
            double jpyToKrw,
            LocalDateTime at,
            Map<String, String> prevSourceMap) {
        return buildKoEstimatedSnapshotsWithAudit(
                cardIds, enMap, jpMap, globalCoefficient,
                usdToKrw, jpyToKrw, at, prevSourceMap, Map.of());
    }

    /**
     * buildKoEstimatedSnapshots + audit metadata 생성용 신규 메서드 (Step B-4a).
     * 기존 메서드와 로직 동일 — 변경점:
     *   1) selectedSourceByCard에 PROMO_DIRECT / PSA10_FALLBACK 도 기록 (audit 일관성)
     *   2) coef 산출 시 resolveCoeffDetail + CoefResolution 사용 (scope/key/value 정확 추적)
     *   3) CARD coef branch도 CoefResolution 명시 (scope=CARD, key=CARD:{cardId}:{JP|EN})
     *   4) applyEraCap 후 새 CoefResolution 만들어 audit에 박을 final value 보존
     *   5) prevAuditMap 인자 — B-4c에서 raw_changed/coef_changed/exchange_rate_changed 비교용
     *
     * audit 생성은 Step B-4c에서 채움. 현재는 List.of() stub (단 위 1~4 메타는 모두 준비).
     */
    private BuildKoResult buildKoEstimatedSnapshotsWithAudit(
            Set<String> cardIds,
            Map<String, PriceSnapshot> enMap,
            Map<String, PriceSnapshot> jpMap,
            double globalCoefficient,
            double usdToKrw,
            double jpyToKrw,
            LocalDateTime at,
            Map<String, String> prevSourceMap,
            Map<String, KoEstimationAudit> prevAuditMap) {
        Map<String, Double> rarityCoeffs = loadRarityCoefficients();
        Map<String, Map<String, Double>> cardCoefs = loadCardCoefficients();
        // Turn D-Round1: market_segment override batch fetch
        Map<String, String> marketSegmentMap = loadMarketSegmentOverrides(cardIds);
        double globalEnFallback = rarityCoeffs.getOrDefault("en_GLOBAL", globalCoefficient);
        double globalJpFallback = rarityCoeffs.getOrDefault("jp_GLOBAL", globalCoefficient);
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds).stream()
                .collect(Collectors.toMap(Card::getCardId, c -> c, (a, b) -> a));
        Map<String, String> selectedSourceByCard = new HashMap<>();

        List<String> promoNoRawIds = cardMap.values().stream()
                .filter(Card::isPromoExclusive)
                .map(Card::getCardId)
                .filter(id -> !jpMap.containsKey(id) && !enMap.containsKey(id))
                .toList();
        Map<String, PriceSnapshot> jpPsa10Map = promoNoRawIds.isEmpty() ? Map.of() :
                priceSnapshotRepository.findLatestScrydexJpPsa10ByCardIds(promoNoRawIds)
                        .stream().collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));

        List<PriceSnapshot> koSnapshots = new ArrayList<>();
        List<KoEstimationAudit> audits = new ArrayList<>(); // B-4c에서 채움
        for (String cardId : cardIds) {
            Card card = cardMap.get(cardId);
            // ───── 프로모 branch ─────
            if (card != null && card.isPromoExclusive()) {
                PriceSnapshot directSrc = jpMap.get(cardId) != null ? jpMap.get(cardId) : enMap.get(cardId);
                Integer koPriceCandidate = null;
                String branchSource = null;
                PriceSnapshot rawForAudit = null; // 분기별 raw snapshot (directSrc 또는 psa)
                if (directSrc != null) {
                    koPriceCandidate = directSrc.getPrice();
                    branchSource = AuditSource.PROMO_DIRECT.name();
                    rawForAudit = directSrc;
                } else {
                    PriceSnapshot psa = jpPsa10Map.get(cardId);
                    if (psa != null && psa.getPrice() > 0) {
                        koPriceCandidate = psa.getPrice();
                        branchSource = AuditSource.PSA10_FALLBACK.name();
                        rawForAudit = psa;
                    }
                }
                if (koPriceCandidate == null || koPriceCandidate <= 0) continue;
                String koSnapshotId = com.fury.back.common.IdGenerator.generate();
                koSnapshots.add(PriceSnapshot.builder()
                        .priceSnapshotId(koSnapshotId)
                        .cardId(cardId).source("KO_ESTIMATED")
                        .price(koPriceCandidate).cardStatus("RAW")
                        .tradedAt(at).collectedAt(at).build());
                selectedSourceByCard.put(cardId, branchSource);
                // B-4c: PROMO_DIRECT / PSA10_FALLBACK audit 생성 (coef_*=null, ranking은 FALLBACK_SOURCE로 제외)
                audits.add(buildAudit(
                        cardId, koSnapshotId, at.toLocalDate(), koPriceCandidate,
                        branchSource,
                        rawForAudit.getPriceSnapshotId(),
                        rawForAudit.getRawPrice(),
                        rawForAudit.getRawCurrency(),
                        BigDecimal.valueOf(koPriceCandidate),
                        rawForAudit.getTradedAt(),
                        null, null, null,
                        BigDecimal.valueOf(usdToKrw), BigDecimal.valueOf(jpyToKrw),
                        prevAuditMap.get(cardId)));
                continue;
            }
            // ───── 일반 selectScrydex branch ─────
            String rarity = card != null && card.getRarityCode() != null ? card.getRarityCode() : "";
            String era = card != null ? resolveEraFromCard(card) : "UNKNOWN";
            PriceSnapshot src = selectScrydexSnapshotForKo(
                    cardId, rarity, jpMap.get(cardId), enMap.get(cardId), usdToKrw, jpyToKrw,
                    prevSourceMap.get(cardId));
            if (src == null) continue;
            boolean isEnSrc = "SCRYDEX_EN".equals(src.getSource());
            String auditSourceName = AuditSource.fromSnapshotSource(src.getSource()).name(); // "JP" / "EN"
            selectedSourceByCard.put(cardId, auditSourceName);
            double srcGlobalFallback = isEnSrc ? globalEnFallback : globalJpFallback;
            String globalFallbackKey = isEnSrc ? "en_GLOBAL" : "jp_GLOBAL";
            Map<String, Double> cardCoef = cardCoefs.get(cardId);
            String cardCoefMapKey = isEnSrc ? "EN" : "JP";
            CoefResolution coefRes;
            if (cardCoef != null && cardCoef.containsKey(cardCoefMapKey)) {
                // CARD coef: era cap 미적용 (raw stored value 그대로)
                double cardCoefValue = cardCoef.get(cardCoefMapKey);
                coefRes = new CoefResolution("CARD",
                        "CARD:" + cardId + ":" + cardCoefMapKey,
                        BigDecimal.valueOf(cardCoefValue));
            } else {
                // Turn D-Round1: MARKET_SEGMENT → RARITY/GLOBAL fallback chain
                // segment lookup도 applyEraCap 적용 (기존 RARITY와 동일 처리 — outlier 방어)
                String segmentKey = marketSegmentMap.get(cardId);
                CoefResolution rawRes = resolveCoeffDetail(
                        rarityCoeffs, src.getSource(), era, rarity, segmentKey, srcGlobalFallback, globalFallbackKey);
                double capped = applyEraCap(src.getSource(), era, rarity, rawRes.value().doubleValue());
                coefRes = new CoefResolution(rawRes.scope(), rawRes.key(), BigDecimal.valueOf(capped));
            }
            double coeffFinal = coefRes.value().doubleValue();
            double srcKrw = toLatestKrw(src, usdToKrw, jpyToKrw);
            int koPrice = (int) Math.round(srcKrw * coeffFinal);
            if (koPrice <= 0) continue;
            String koSnapshotId = com.fury.back.common.IdGenerator.generate();
            koSnapshots.add(PriceSnapshot.builder()
                    .priceSnapshotId(koSnapshotId)
                    .cardId(cardId).source("KO_ESTIMATED")
                    .price(koPrice).cardStatus("RAW")
                    .tradedAt(at).collectedAt(at).build());
            // B-4c: 일반 JP/EN audit 생성. selectedRawPriceKrw는 KO 산출에 쓴 동일 KRW 값.
            audits.add(buildAudit(
                    cardId, koSnapshotId, at.toLocalDate(), koPrice,
                    auditSourceName,
                    src.getPriceSnapshotId(),
                    src.getRawPrice(),
                    src.getRawCurrency(),
                    BigDecimal.valueOf(srcKrw),
                    src.getTradedAt(),
                    coefRes.scope(), coefRes.key(), coefRes.value(),
                    BigDecimal.valueOf(usdToKrw), BigDecimal.valueOf(jpyToKrw),
                    prevAuditMap.get(cardId)));
        }
        return new BuildKoResult(koSnapshots, selectedSourceByCard, audits);
    }

    /** 카드별 KO 예상가 히스토리 (차트용) */
    public List<Map<String, Object>> getKoEstimatedHistory(String cardId, int days) {
        LocalDateTime after = LocalDateTime.now().minusDays(days);
        return priceSnapshotRepository.findKoEstimatedHistory(cardId, after).stream()
                .map(s -> {
                    Map<String, Object> m = new java.util.LinkedHashMap<>();
                    m.put("date",  s.getTradedAt().toLocalDate().toString());
                    m.put("price", s.getPrice());
                    return m;
                })
                .toList();
    }

    /** 최근 N일 계수 히스토리 (그래프용) */
    public List<Map<String, Object>> getCoefficientHistory(int days) {
        List<PriceSnapshot> history = priceSnapshotRepository
                .findByCardIdAndSourceOrderByTradedAtAsc(COEFF_CARD_ID, COEFF_SOURCE);
        LocalDateTime cutoff = LocalDateTime.now().minusDays(days);
        return history.stream()
                .filter(s -> s.getTradedAt().isAfter(cutoff))
                .map(s -> {
                    Map<String, Object> m = new java.util.LinkedHashMap<>();
                    m.put("date",        s.getTradedAt().toLocalDate().toString());
                    m.put("coefficient", s.getPrice() / 10000.0);
                    return m;
                })
                .toList();
    }

    // ─────────────────────────────────────────────
    // 5. 수동 카드 매핑 (card_id → scrydex ref)
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
                    HIGH_RARE_CODES, "KO").stream()
                    .filter(c -> (c.getJpScrydexRef() == null || c.getJpScrydexRef().isBlank())
                              && (c.getEnScrydexRef() == null || c.getEnScrydexRef().isBlank()))
                    .toList();
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

        Optional<ScrydexLivePriceDto> enResult = Optional.empty();
        if (enRef != null && !enRef.isBlank() && !enRef.startsWith("NO_")) {
            enResult = scrydexLiveClient.fetchPrices(enRef, "EN");
            if (enResult.isPresent() && enResult.get().getRawNm() != null) return enResult;
        }
        Optional<ScrydexLivePriceDto> jpResult = Optional.empty();
        if (jpRef != null && !jpRef.isBlank() && !jpRef.startsWith("NO_")) {
            jpResult = scrydexLiveClient.fetchPrices(jpRef, "JP");
            if (jpResult.isPresent() && jpResult.get().getRawNm() != null) return jpResult;
        }
        if (enResult.isPresent()) return enResult;
        if (jpResult.isPresent()) return jpResult;
        return Optional.empty();
    }

    @Transactional
    public Map<String, Object> triggerPriceFetchForCard(String cardId) {
        Card card = cardRepository.findById(cardId).orElse(null);
        if (card == null) {
            return Map.of("success", false, "message", "카드를 찾을 수 없습니다. cardId=" + cardId);
        }

        LocalDateTime now = LocalDateTime.now();
        double usdToKrw = exchangeRateClient.getUsdToKrw();
        int scrydexSaved = 0;
        ScrydexSaveResult enSave = fetchAndSaveScrydexSnapshots(card, card.getEnScrydexRef(), "EN", "SCRYDEX_EN", usdToKrw, now);
        scrydexSaved += enSave.savedCount();
        PriceSnapshot enSnapshot = enSave.rawSnapshot();
        ScrydexSaveResult jpSave = fetchAndSaveScrydexSnapshots(card, card.getJpScrydexRef(), "JP", "SCRYDEX_JP", usdToKrw, now);
        scrydexSaved += jpSave.savedCount();
        PriceSnapshot jpSnapshot = jpSave.rawSnapshot();

        List<String> singleCard = List.of(cardId);
        if (enSnapshot == null) {
            enSnapshot = priceSnapshotRepository.findLatestScrydexEnByCardIds(singleCard)
                    .stream().findFirst().orElse(null);
        }
        if (jpSnapshot == null) {
            jpSnapshot = priceSnapshotRepository.findLatestScrydexJpByCardIds(singleCard)
                    .stream().findFirst().orElse(null);
        }

        Integer koEstimated = calculateKoEstimatedForCard(card, enSnapshot, jpSnapshot, usdToKrw);
        boolean koSaved = false;
        if (koEstimated != null && koEstimated > 0) {
            saveKoEstimatedForCard(cardId, koEstimated);
            koSaved = true;
        }

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("success", true);
        result.put("cardId", cardId);
        result.put("scrydexSaved", scrydexSaved);
        result.put("koEstimatedSaved", koSaved);
        result.put("koEstimatedPrice", koEstimated);
        return result;
    }

    private ScrydexSaveResult fetchAndSaveScrydexSnapshots(
            Card card,
            String ref,
            String region,
            String source,
            double usdToKrw,
            LocalDateTime now) {
        if (ref == null || ref.isBlank() || ref.startsWith("NO_")) return new ScrydexSaveResult(null, 0);
        Optional<ScrydexLivePriceDto> live = scrydexLiveClient.fetchPrices(ref, region);
        if (live.isEmpty()) return new ScrydexSaveResult(null, 0);

        ScrydexLivePriceDto dto = live.get();
        int savedCount = 0;
        PriceSnapshot rawSnapshot = null;
        if (dto.getRawNm() != null && dto.getRawNm() > 0) {
            rawSnapshot = buildScrydexSnapshot(card, ref, source, dto.getRawNm(), "RAW", null, null, now, usdToKrw);
            priceSnapshotRepository.save(rawSnapshot);
            savedCount++;
        }
        if (dto.getPsa10() != null && dto.getPsa10() > 0) {
            priceSnapshotRepository.save(buildScrydexSnapshot(card, ref, source, dto.getPsa10(), "GRADED", "PSA", "10", now, usdToKrw));
            savedCount++;
        }
        if (dto.getPsa9() != null && dto.getPsa9() > 0) {
            priceSnapshotRepository.save(buildScrydexSnapshot(card, ref, source, dto.getPsa9(), "GRADED", "PSA", "9", now, usdToKrw));
            savedCount++;
        }
        return new ScrydexSaveResult(rawSnapshot, savedCount);
    }

    private PriceSnapshot buildScrydexSnapshot(
            Card card,
            String ref,
            String source,
            Double rawUsd,
            String cardStatus,
            String gradingCompany,
            String gradeValue,
            LocalDateTime now,
            double usdToKrw) {
        return PriceSnapshot.builder()
                .priceSnapshotId(com.fury.back.common.IdGenerator.generate())
                .cardId(card.getCardId())
                .source(source)
                .sourceItemId(truncate(ref, 100))
                .price((int) Math.round(rawUsd * usdToKrw))
                .rawPrice(BigDecimal.valueOf(rawUsd))
                .rawCurrency("USD")
                .cardStatus(cardStatus)
                .gradingCompany(gradingCompany)
                .gradeValue(gradeValue)
                .tradedAt(now)
                .collectedAt(now)
                .build();
    }

    private String truncate(String value, int maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }

    private record ScrydexSaveResult(PriceSnapshot rawSnapshot, int savedCount) {
    }

    private Integer calculateKoEstimatedForCard(
            Card card,
            PriceSnapshot enSnapshot,
            PriceSnapshot jpSnapshot,
            double usdToKrw) {
        String rarity = card.getRarityCode() != null ? card.getRarityCode() : "";
        String era = resolveEraFromCard(card);
        double globalCoefficient = getLatestCoefficientValue();
        Map<String, Double> allCoeffs = loadRarityCoefficients();
        double globalEnRatio = allCoeffs.getOrDefault("en_GLOBAL", globalCoefficient);
        double globalJpRatio = allCoeffs.getOrDefault("jp_GLOBAL", globalCoefficient);
        double enRatio = applyEraCap("SCRYDEX_EN", era, rarity,
                resolveCoeff(allCoeffs, "SCRYDEX_EN", era, rarity, globalEnRatio));
        double jpRatio = applyEraCap("SCRYDEX_JP", era, rarity,
                resolveCoeff(allCoeffs, "SCRYDEX_JP", era, rarity, globalJpRatio));
        double jpyToKrw = exchangeRateClient.getJpyToKrw();

        PriceSnapshot src = selectScrydexSnapshotForKo(
                card.getCardId(), rarity, jpSnapshot, enSnapshot, usdToKrw, jpyToKrw, null);
        if (src == null) return null;
        double ratio = "SCRYDEX_JP".equals(src.getSource()) ? jpRatio : enRatio;
        int koPrice = (int) Math.round(toLatestKrw(src, usdToKrw, jpyToKrw) * ratio);
        return koPrice > 0 ? koPrice : null;
    }

    public List<PriceSnapshotDto> getGlobalHistory(String cardId) {
        List<String> globalSources = List.of("SCRYDEX_JP", "SCRYDEX_EN");
        return priceSnapshotRepository
                .findByCardIdAndSourceInAndCardStatusOrderByTradedAtDesc(cardId, globalSources, "RAW")
                .stream()
                .map(PriceSnapshotDto::from)
                .toList();
    }

    public Integer getStoredKoPrice(String cardId) {
        return priceSnapshotRepository
                .findLatestKoEstimatedByCardIds(List.of(cardId))
                .stream().findFirst()
                .map(PriceSnapshot::getPrice)
                .orElse(null);
    }

    /** 상세 화면에서 계산된 KO 예상가를 DB에 저장 (하루 1번만) */
    @Transactional
    public void saveKoEstimatedForCard(String cardId, int koPrice) {
        if (koPrice <= 0) return;
        LocalDateTime now = LocalDateTime.now();
        boolean exists = priceSnapshotRepository
                .existsByCardIdAndSourceAndTradedAtAfter(cardId, "KO_ESTIMATED", now.toLocalDate().atStartOfDay());
        if (exists) return;
        PriceSnapshot snapshot = PriceSnapshot.builder()
                .priceSnapshotId(com.fury.back.common.IdGenerator.generate())
                .cardId(cardId)
                .source("KO_ESTIMATED")
                .price(koPrice)
                .cardStatus("RAW")
                .tradedAt(now)
                .collectedAt(now)
                .build();
        priceSnapshotRepository.save(snapshot);
        log.debug("[KoEstimated] 저장: cardId={}, price={}", cardId, koPrice);
    }

    /** 현재 시장 보정 계수 조회 (미설정 시 1.0) */
    public Map<String, Object> getMarketAdjustment() {
        List<PriceSnapshot> rows = priceSnapshotRepository.findLatestMarketAdjustment();
        double factor = rows.isEmpty() ? 1.0 : rows.get(0).getPrice() / 10000.0;
        return Map.of("factor", factor);
    }

    /** 시장 보정 계수 변경 → ko_coef_* 전체 비율 업데이트 → KO_ESTIMATED 재계산 */
    @Transactional
    public Map<String, Object> setMarketAdjustment(double newFactor) {
        if (newFactor <= 0 || newFactor > 5.0) throw new IllegalArgumentException("factor 범위 초과: " + newFactor);

        double currentFactor = priceSnapshotRepository.findLatestMarketAdjustment()
                .stream().findFirst().map(s -> s.getPrice() / 10000.0).orElse(1.0);
        double ratio = newFactor / currentFactor;

        priceSnapshotRepository.applyAdjustmentRatioToCoefficients(ratio);
        log.info("[MarketAdj] {} → {} (ratio={})", currentFactor, newFactor, String.format("%.4f", ratio));

        LocalDateTime now = LocalDateTime.now();
        priceSnapshotRepository.save(PriceSnapshot.builder()
                .priceSnapshotId(com.fury.back.common.IdGenerator.generate())
                .cardId("ko_adjustment_factor").source("SYSTEM")
                .price((int) Math.round(newFactor * 10000)).cardStatus("RAW")
                .tradedAt(now).collectedAt(now).build());

        Map<String, Object> result = new HashMap<>(refreshKoEstimatesFromSnapshots());
        result.put("adjustmentFactor", newFactor);
        result.put("previousFactor", currentFactor);
        result.put("ratio", Math.round(ratio * 10000.0) / 10000.0);
        return result;
    }

    /**
     * 배치: era-aware 계수 + JP/EN guard 적용하여 KO_ESTIMATED 전량 재계산. 강제 덮어쓰기.
     */
    @Transactional
    public Map<String, Object> refreshKoEstimatesFromSnapshots() {
        MarketCoefficientDto coeff = getCoefficient();
        double globalCoefficient = coeff.getCoefficient();
        double usdToKrw = exchangeRateClient.getUsdToKrw();
        double jpyToKrw = exchangeRateClient.getJpyToKrw();
        LocalDateTime now = LocalDateTime.now();

        List<PriceSnapshot> enSnapshots = priceSnapshotRepository.findAllLatestScrydexEn();
        List<PriceSnapshot> jpSnapshots = priceSnapshotRepository.findAllLatestScrydexJp();
        Map<String, PriceSnapshot> enMap = enSnapshots.stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));
        Map<String, PriceSnapshot> jpMap = jpSnapshots.stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));
        Set<String> allIds = new java.util.HashSet<>(enMap.keySet());
        allIds.addAll(jpMap.keySet());

        int saved = 0;
        int savedAudits = 0;
        if (!allIds.isEmpty()) {
            // Turn C-1 (2026-05-17): legacy inferPrevKoSources fallback 유지 + audit prevSource override.
            // 첫 실행 시 audit 비어있으면 prevSourceMap이 텅 비어 hysteresis가 꺼지므로,
            // legacy를 base로 깔고 audit 있는 카드만 audit selectedSource로 덮어쓴다.
            LocalDate yesterday = LocalDate.now().minusDays(1);
            Map<String, Double> rarityCoeffsForInfer = loadRarityCoefficients();
            Map<String, Map<String, Double>> cardCoefsForInfer = loadCardCoefficients();
            Map<String, String> legacyPrevSourceMap = inferPrevKoSources(
                    yesterday, allIds, rarityCoeffsForInfer, cardCoefsForInfer, usdToKrw, jpyToKrw);
            Map<String, KoEstimationAudit> prevAuditMap = inferPrevAudits(yesterday, allIds);
            Map<String, String> auditPrevSourceMap = prevAuditMap.entrySet().stream()
                    .collect(Collectors.toMap(Map.Entry::getKey, e -> e.getValue().getSelectedSource()));
            Map<String, String> prevSourceMap = new HashMap<>(legacyPrevSourceMap);
            prevSourceMap.putAll(auditPrevSourceMap); // audit 있으면 audit 우선

            BuildKoResult buildResult = buildKoEstimatedSnapshotsWithAudit(
                    allIds, enMap, jpMap, globalCoefficient, usdToKrw, jpyToKrw, now,
                    prevSourceMap, prevAuditMap);
            List<PriceSnapshot> koSnapshots = buildResult.snapshots();
            List<KoEstimationAudit> audits = buildResult.audits();

            // 1:1 보장 검증 — mismatch 시 rollback (KREAM promo는 buildKo 경로 아니므로 여기 제외)
            if (koSnapshots.size() != audits.size()) {
                throw new IllegalStateException(String.format(
                        "[KoEstimated/Audit] count mismatch: snapshots=%d, audits=%d",
                        koSnapshots.size(), audits.size()));
            }

            if (!koSnapshots.isEmpty()) {
                List<String> cardIdList = koSnapshots.stream().map(PriceSnapshot::getCardId).toList();
                priceSnapshotRepository.deleteTodayKoEstimated(cardIdList); // FK CASCADE로 기존 audit도 삭제
                priceSnapshotRepository.saveAll(koSnapshots);
                priceSnapshotRepository.flush(); // FK constraint 위해 audit insert 전 snapshot row 확정
                koAuditRepository.saveAll(audits);
                saved = koSnapshots.size();
                savedAudits = audits.size();
            }
        }

        // KO 독점 프로모 카드(NO_EN/NO_JP) → KREAM 체결가 기반 KO_ESTIMATED 추가 저장.
        // 일반 scrydex 경로에서 빠지는 카드(예: 메타몽 Pokemon Town 2025)를 보완.
        // 주의: KREAM promo는 buildKo 경로가 아니므로 audit 미생성 (Turn C-2/D 별도 처리).
        int promoSaved = savePromoKoEstimatedFromKream(now);

        log.info("[KoEstimated] refresh 완료: {}장 KO 예상가 저장 (audit {}장, KREAM promo {}장)",
                saved + promoSaved, savedAudits, promoSaved);
        return Map.of(
            "coefficient", globalCoefficient,
            "exchangeRate", usdToKrw,
            "savedCount", saved + promoSaved,
            "savedAudits", savedAudits,
            "promoSavedCount", promoSaved,
            "enSource", enSnapshots.size(),
            "jpSource", jpSnapshots.size(),
            "status", "refreshed"
        );
    }

    /**
     * KREAM 등급별 일별 시계열을 차트 포인트로 변환. 1포인트만이면 30일 전 + 오늘로 평탄선 합성
     * (line 그리려면 최소 2 포인트 필요. KREAM_CHART formula 평탄선과 동일 패턴).
     */
    private List<CardPriceSummaryDto.ChartPoint> mapKreamGradedSeries(List<Object[]> rows) {
        if (rows.isEmpty()) return List.of();
        List<CardPriceSummaryDto.ChartPoint> points = rows.stream()
                .map(r -> new CardPriceSummaryDto.ChartPoint(
                        (String) r[0],
                        ((Number) r[1]).doubleValue(),
                        null, null))
                .toList();
        if (points.size() == 1) {
            double price = points.get(0).price();
            return List.of(
                    new CardPriceSummaryDto.ChartPoint(LocalDate.now().minusDays(CHART_WINDOW_DAYS).toString(), price, null, null),
                    new CardPriceSummaryDto.ChartPoint(LocalDate.now().toString(), price, null, null)
            );
        }
        return points;
    }

    /**
     * NO_EN/NO_JP 프로모 카드의 KO_ESTIMATED를 KREAM Ungraded 체결가로 채움.
     * 일반 scrydex 기반 KO_ESTIMATED 경로는 이 카드들을 못 처리하므로 보완용.
     */
    private int savePromoKoEstimatedFromKream(LocalDateTime now) {
        List<Object[]> rows = priceSnapshotRepository.findLatestKreamRawForKoExclusivePromos();
        if (rows.isEmpty()) {
            return 0;
        }
        List<String> cardIds = rows.stream().map(r -> (String) r[0]).toList();
        priceSnapshotRepository.deleteTodayKoEstimated(cardIds);

        List<PriceSnapshot> snaps = rows.stream()
                .map(r -> PriceSnapshot.builder()
                        .priceSnapshotId(com.fury.back.common.IdGenerator.generate())
                        .cardId((String) r[0])
                        .source("KO_ESTIMATED")
                        .price(((Number) r[1]).intValue())
                        .cardStatus("RAW")
                        .tradedAt(now)
                        .collectedAt(now)
                        .build())
                .toList();
        priceSnapshotRepository.saveAll(snaps);
        log.info("[KoEstimated/Promo] KREAM 기반 {}장 KO 독점 프로모 KO_ESTIMATED 저장", snaps.size());
        return snaps.size();
    }

    /**
     * 라이브 배치: scrydex ref가 있는 모든 카드의 실시간 가격 조회 → KO_ESTIMATED + SCRYDEX 스냅샷 저장.
     * 오늘 이미 저장된 카드는 스킵. 백그라운드 스레드에서 실행 (즉시 반환).
     */
    public Map<String, Object> startRefreshKoEstimatesLive() {
        MarketCoefficientDto coeff = getCoefficient();
        double globalCoefficient = coeff.getCoefficient();
        double exchangeRate = coeff.getExchangeRate();
        Map<String, Double> allCoeffs = loadRarityCoefficients();

        List<Card> cardsWithRefs = cardRepository.findAll().stream()
                .filter(c -> (c.getEnScrydexRef() != null && !c.getEnScrydexRef().startsWith("NO_"))
                          || (c.getJpScrydexRef() != null && !c.getJpScrydexRef().startsWith("NO_")))
                .toList();

        log.info("[KoLive] 배치 시작: {}장 대상", cardsWithRefs.size());
        new Thread(() -> {
            int saved = 0, failed = 0;
            LocalDateTime now = LocalDateTime.now();
            for (Card card : cardsWithRefs) {
                try {
                    String rarity = card.getRarityCode() != null ? card.getRarityCode() : "";
                    String era = resolveEraFromCard(card);
                    double enRatio = applyEraCap(SOURCE_SCRYDEX_EN, era, rarity,
                            resolveCoeff(allCoeffs, SOURCE_SCRYDEX_EN, era, rarity, globalCoefficient));
                    double jpRatio = applyEraCap("SCRYDEX_JP", era, rarity,
                            resolveCoeff(allCoeffs, "SCRYDEX_JP", era, rarity, globalCoefficient));

                    // SCRYDEX_JP/EN 저장은 Python 배치 전담 — Java live 배치는 기존 DB 값으로 KO만 계산
                    List<String> singleCard = List.of(card.getCardId());
                    PriceSnapshot existingJp = priceSnapshotRepository.findLatestScrydexJpByCardIds(singleCard)
                            .stream().findFirst().orElse(null);
                    PriceSnapshot existingEn = priceSnapshotRepository.findLatestScrydexEnByCardIds(singleCard)
                            .stream().findFirst().orElse(null);

                    double usdToKrw2 = exchangeRate;
                    double jpyToKrw2 = exchangeRateClient.getJpyToKrw();
                    PriceSnapshot src = selectScrydexSnapshotForKo(
                            card.getCardId(), rarity, existingJp, existingEn, usdToKrw2, jpyToKrw2, null);
                    if (src == null) { failed++; continue; }

                    double ratio2 = "SCRYDEX_JP".equals(src.getSource()) ? jpRatio : enRatio;
                    Integer koPrice = (int) Math.round(toLatestKrw(src, usdToKrw2, jpyToKrw2) * ratio2);
                    if (koPrice <= 0) { failed++; continue; }

                    if (koPrice == null || koPrice <= 0) { failed++; continue; }

                    priceSnapshotRepository.save(PriceSnapshot.builder()
                            .priceSnapshotId(com.fury.back.common.IdGenerator.generate())
                            .cardId(card.getCardId()).source("KO_ESTIMATED")
                            .price(koPrice).cardStatus("RAW")
                            .tradedAt(now).collectedAt(now).build());
                    saved++;
                } catch (Exception e) {
                    log.error("[KoLive] 실패: {}", card.getCardId(), e); failed++;
                }
            }
            log.info("[KoLive] 완료: saved={}, failed={}", saved, failed);
        }).start();

        return Map.of("status", "started", "total", cardsWithRefs.size(),
                "coefficient", globalCoefficient, "exchangeRate", exchangeRate,
                "message", "백그라운드 실행 중 — 서버 로그에서 진행 확인");
    }

    /** 특정 레어도 계수 조회: JP 계수 우선, 없으면 EN/글로벌 폴백 */
    public double getCoefficientForRarity(String rarityCode) {
        Map<String, Double> rarityCoeffs = loadRarityCoefficients();
        double globalCoeff = getCoefficient().getCoefficient();
        return rarityCoeffs.getOrDefault("jp_" + rarityCode,
                rarityCoeffs.getOrDefault("en_" + rarityCode,
                        rarityCoeffs.getOrDefault("jp_GLOBAL",
                                rarityCoeffs.getOrDefault("en_GLOBAL", globalCoeff))));
    }

    // ─────────────────────────────────────────────
    // 상세 화면 단일 집계 엔드포인트
    // ─────────────────────────────────────────────

    public CardPriceSummaryDto getCardPriceSummary(String cardId) {
        Card card = cardRepository.findById(cardId).orElse(null);
        if (card == null) return null;

        // 캐시에서만 읽기 — 캐시 미스여도 재계산 없이 DB 히스토리 마지막값 사용
        // (getCoefficient() 호출 시 캐시 미스 → recalculateCoefficient() → 대규모 DB 처리 → 느림)
        double globalCoeff;
        double exchangeRate;
        MarketCoefficientDto cached = coefficientCache.getOrNull();
        if (cached != null) {
            globalCoeff  = cached.getCoefficient();
            exchangeRate = cached.getExchangeRate();
        } else {
            List<PriceSnapshot> history = priceSnapshotRepository
                    .findByCardIdAndSourceOrderByTradedAtAsc(COEFF_CARD_ID, COEFF_SOURCE);
            if (!history.isEmpty()) {
                globalCoeff = history.get(history.size() - 1).getPrice() / 10000.0;
            } else {
                globalCoeff = 1.0;
            }
            exchangeRate = 1400.0;
        }

        // 레어도별 계수 + EN/JP→KO 비율 (era-aware, saveKoEstimatedSnapshots와 동일 로직)
        Map<String, Double> allCoeffs = loadRarityCoefficients();
        String rarity = card.getRarityCode() != null ? card.getRarityCode() : "";
        String era = resolveEraFromCard(card);
        double globalEnRatio = allCoeffs.getOrDefault("en_GLOBAL", globalCoeff);
        double globalJpRatio = allCoeffs.getOrDefault("jp_GLOBAL", globalCoeff);
        double enRatio = applyEraCap("SCRYDEX_EN", era, rarity,
                resolveCoeff(allCoeffs, "SCRYDEX_EN", era, rarity, globalEnRatio));
        double jpRatio = applyEraCap("SCRYDEX_JP", era, rarity,
                resolveCoeff(allCoeffs, "SCRYDEX_JP", era, rarity, globalJpRatio));

        // ── SCRYDEX 히스토리 90일 (EN/JP 차트 + KO 추정선 공용)
        LocalDateTime chartCutoff = LocalDateTime.now().minusDays(CHART_WINDOW_DAYS);
        List<PriceSnapshot> enSnapsHistory = priceSnapshotRepository
                .findByCardIdAndSourceAndTradedAtAfterOrderByTradedAtAsc(cardId, "SCRYDEX_EN", chartCutoff);
        List<PriceSnapshot> jpSnapsHistory = priceSnapshotRepository
                .findByCardIdAndSourceAndTradedAtAfterOrderByTradedAtAsc(cardId, "SCRYDEX_JP", chartCutoff);
        log.debug("[KoLine] card={} rarity={} enRatio={} jpRatio={} enSnaps={} jpSnaps={}",
                cardId, rarity, String.format("%.3f", enRatio), String.format("%.3f", jpRatio),
                enSnapsHistory.size(), jpSnapsHistory.size());

        boolean promoExclusive = card.isPromoExclusive();
        // ── KO 추정선: 저장된 KO_ESTIMATED 히스토리 우선, 부족하면 기존 SCRYDEX 기반 계산 폴백
        double jpyToKrw = exchangeRateClient.getJpyToKrw();
        List<PriceSnapshot> koEstHistory = priceSnapshotRepository
                .findByCardIdAndSourceAndTradedAtAfterOrderByTradedAtAsc(cardId, "KO_ESTIMATED", chartCutoff);
        List<CardPriceSummaryDto.ChartPoint> koLine = !promoExclusive && koEstHistory.size() >= 2
                ? koEstHistory.stream()
                        .map(s -> new CardPriceSummaryDto.ChartPoint(
                                s.getTradedAt().toLocalDate().toString(),
                                s.getPrice().doubleValue(), null, null))
                        .toList()
                : buildKoLineFromSnaps(
                        enSnapsHistory, jpSnapsHistory, enRatio, jpRatio, rarity, exchangeRate, jpyToKrw);

        // ── price_snapshots에서 EN/JP RAW 최신가 읽기 (리스트와 동일 소스)
        List<String> singleId = List.of(cardId);
        PriceSnapshot enRawSnap = priceSnapshotRepository.findLatestScrydexEnByCardIds(singleId)
                .stream().findFirst().orElse(null);
        PriceSnapshot jpRawSnap = priceSnapshotRepository.findLatestScrydexJpByCardIds(singleId)
                .stream().findFirst().orElse(null);
        PriceSnapshot koEstimatedSnap = priceSnapshotRepository.findLatestKoEstimatedByCardIds(singleId)
                .stream().findFirst().orElse(null);

        Integer formulaPrice;
        String formulaBasis;

        if (promoExclusive) {
            // 프로모 카드: JP RAW 우선, 없으면 PSA10 기준, 그것도 없으면 EN RAW
            PriceSnapshot jpPsa10Snap = null;
            if (jpRawSnap == null) {
                jpPsa10Snap = priceSnapshotRepository.findLatestScrydexJpPsa10ByCardIds(singleId)
                        .stream().findFirst().orElse(null);
            }
            if (jpRawSnap != null) {
                formulaPrice = jpRawSnap.getPrice();
                formulaBasis = "SCRYDEX_JP_DIRECT";
            } else if (jpPsa10Snap != null) {
                // 평균 ratio 추정 비활성(2026-05-13) — 인기 한정판 자산 평가 왜곡 우려.
                // 데이터 보강 전까지 PSA10 그대로 (legacy).
                formulaPrice = jpPsa10Snap.getPrice();
                formulaBasis = "SCRYDEX_JP_PSA10";
            } else if (enRawSnap != null) {
                formulaPrice = enRawSnap.getPrice();
                formulaBasis = "SCRYDEX_EN_DIRECT";
            } else {
                formulaPrice = null;
                formulaBasis = "SCRYDEX_DIRECT";
            }
            // koLine: RAW 히스토리 우선, 없으면 PSA10 히스토리 사용
            List<PriceSnapshot> jpRawHistory = jpSnapsHistory.stream()
                    .filter(s -> "RAW".equals(s.getCardStatus()))
                    .toList();
            List<PriceSnapshot> jpPsa10History = jpSnapsHistory.stream()
                    .filter(s -> "GRADED".equals(s.getCardStatus())
                            && "PSA".equals(s.getGradingCompany()) && "10".equals(s.getGradeValue()))
                    .toList();
            List<PriceSnapshot> enRawHistory = enSnapsHistory.stream()
                    .filter(s -> "RAW".equals(s.getCardStatus()))
                    .toList();
            List<PriceSnapshot> koLineSource = !jpRawHistory.isEmpty() ? jpRawHistory
                    : (!jpPsa10History.isEmpty() ? jpPsa10History : enRawHistory);
            if (!koLineSource.isEmpty()) {
                koLine = koLineSource.stream()
                        .map(s -> new CardPriceSummaryDto.ChartPoint(
                                s.getTradedAt().toLocalDate().toString(),
                                s.getPrice().doubleValue(), null, null))
                        .toList();
            }
        } else {
            Integer koFromEn = enRawSnap != null ? (int) Math.round(enRawSnap.getPrice() * enRatio) : null;
            PriceSnapshot formulaSnap = selectScrydexSnapshotForKo(
                    cardId, rarity, jpRawSnap, enRawSnap, exchangeRate, jpyToKrw, null);
            formulaPrice = formulaSnap == null ? null
                    : (int) Math.round(formulaSnap.getPrice() *
                    ("SCRYDEX_JP".equals(formulaSnap.getSource()) ? jpRatio : enRatio));
            if (formulaPrice == null) formulaPrice = koFromEn;
            formulaBasis = "FORMULA";
        }

        if (!promoExclusive && koEstimatedSnap != null) {
            formulaPrice = koEstimatedSnap.getPrice();
            formulaBasis = "KO_ESTIMATED";
        }

        // NO_EN/NO_JP 카드(메타몽 Pokemon Town 2025 등): SCRYDEX 시계열 없으므로 KREAM 시계열로 채움.
        // line = KREAM_CHART 일별 종합, psa10/9Line = KREAM source 등급별 일별 적층.
        // EN/JP 차트가 line+psa10Line+psa9Line으로 그리는 패턴을 KO에도 동일 적용.
        List<CardPriceSummaryDto.ChartPoint> koPsa10Line = List.of();
        List<CardPriceSummaryDto.ChartPoint> koPsa9Line  = List.of();
        boolean noExternalRef = (card.getEnScrydexRef() == null
                || card.getEnScrydexRef().isBlank()
                || card.getEnScrydexRef().startsWith("NO_"))
                && (card.getJpScrydexRef() == null
                || card.getJpScrydexRef().isBlank()
                || card.getJpScrydexRef().startsWith("NO_"));
        if (!promoExclusive && noExternalRef) {
            // 모든 line이 동일 패턴(mapKreamGradedSeries): KREAM source의 등급별 일별 시계열 + 1포인트 평탄선 합성.
            // KREAM_CHART(KREAM의 일별 종합 가격 — RAW/PSA 섞임)은 사용 안 함, 의미 왜곡 방지.
            List<CardPriceSummaryDto.ChartPoint> rawLine = mapKreamGradedSeries(
                    priceSnapshotRepository.findKreamRawSeries(cardId, chartCutoff));
            if (!rawLine.isEmpty()) {
                koLine = rawLine;
            }
            koPsa10Line = mapKreamGradedSeries(
                    priceSnapshotRepository.findKreamGradedSeries(cardId, "PSA", "10", chartCutoff));
            koPsa9Line = mapKreamGradedSeries(
                    priceSnapshotRepository.findKreamGradedSeries(cardId, "PSA", "9", chartCutoff));
        }

        // scrydex 데이터 부족 시 formulaPrice로 평탄선 합성 — 항상 차트 표시
        if (koLine.size() < 2 && formulaPrice != null) {
            double fp = formulaPrice.doubleValue();
            koLine = List.of(
                    new CardPriceSummaryDto.ChartPoint(LocalDate.now().minusDays(CHART_WINDOW_DAYS).toString(), fp, null, null),
                    new CardPriceSummaryDto.ChartPoint(LocalDate.now().toString(), fp, null, null)
            );
        }

        // NAVER_CAFE/BUNJANG은 계수 계산용 데이터이므로 상세 표시 가격/차트에는 사용하지 않는다.
        List<CardPriceSummaryDto.ChartPoint> koPoints = List.of();

        // ── KO 차트 = 추정선 + (NO_EN/NO_JP 카드에 한해서) KREAM 등급별 보조선
        CardPriceSummaryDto.ChartData koChart;
        if (koLine.size() >= 2) {
            String koChartType = koPoints.isEmpty() ? "LINE" : "LINE_WITH_POINTS";
            koChart = new CardPriceSummaryDto.ChartData(koChartType, "OK", koLine, koPoints, koPsa10Line, koPsa9Line);
        } else if (!koPoints.isEmpty()) {
            koChart = new CardPriceSummaryDto.ChartData("POINTS", "OK", List.of(), koPoints, koPsa10Line, koPsa9Line);
        } else {
            koChart = new CardPriceSummaryDto.ChartData("NONE", "INSUFFICIENT_DATA", List.of(), List.of(), koPsa10Line, koPsa9Line);
        }

        // ── KO mid 산출
        double baseMid = formulaPrice != null ? formulaPrice.doubleValue()
                : (koLine.isEmpty() ? 0 : koLine.get(koLine.size() - 1).price());
        Integer koMid;
        String koBasis;
        int koDomesticCount = 0;

        if (baseMid > 0) {
            koMid = (int) Math.round(baseMid);
            koBasis = formulaBasis;
        } else {
            koMid   = formulaPrice;
            koBasis = formulaBasis;
        }

        Integer koLow  = koMid != null ? roundPrice((int) Math.round(koMid * 0.85)) : null;
        Integer koHigh = koMid != null ? roundPrice((int) Math.round(koMid * 1.15)) : null;

        // ── EN/JP 차트 (앞서 로드한 히스토리 재사용, filterJumps로 scrydex 데이터 오류 제거)
        List<CardPriceSummaryDto.ChartPoint> enLine      = filterJumps(snapsToPoints(enSnapsHistory, exchangeRate), 0.6);
        List<CardPriceSummaryDto.ChartPoint> enPsa10Line = psaSnapsToPoints(
                priceSnapshotRepository.findScrydexPsaHistory(cardId, "SCRYDEX_EN", "10", chartCutoff), exchangeRate);
        List<CardPriceSummaryDto.ChartPoint> enPsa9Line  = psaSnapsToPoints(
                priceSnapshotRepository.findScrydexPsaHistory(cardId, "SCRYDEX_EN", "9", chartCutoff), exchangeRate);

        List<CardPriceSummaryDto.ChartPoint> jpLine      = filterJumps(snapsToPoints(jpSnapsHistory, exchangeRate), 0.6);
        List<CardPriceSummaryDto.ChartPoint> jpPsa10Line = psaSnapsToPoints(
                priceSnapshotRepository.findScrydexPsaHistory(cardId, "SCRYDEX_JP", "10", chartCutoff), exchangeRate);
        List<CardPriceSummaryDto.ChartPoint> jpPsa9Line  = psaSnapsToPoints(
                priceSnapshotRepository.findScrydexPsaHistory(cardId, "SCRYDEX_JP", "9", chartCutoff), exchangeRate);

        // DB에 PSA 데이터 없으면 scrydex API 폴백 (배치 미실행 카드)
        if (enPsa10Line.isEmpty() && enPsa9Line.isEmpty() && jpPsa10Line.isEmpty() && jpPsa9Line.isEmpty()) {
            Optional<ScrydexHistoryDto> enH = getScrydexHistory(cardId, "EN");
            enH.ifPresent(h -> {
                // mutable locals workaround — 폴백이므로 지역 변수 재할당 불가, 직접 반영
            });
            // 폴백: scrydexLiveClient에서 현재가만 가져옴 (히스토리는 배치 후 채워짐)
        }

        // PSA 현재가 = 최신 스냅샷 마지막 포인트
        CardPriceSummaryDto.PsaPrices enPsa = extractPsa(enPsa10Line, enPsa9Line);
        CardPriceSummaryDto.PsaPrices jpPsa = extractPsa(jpPsa10Line, jpPsa9Line);

        // PSA 현재가 없으면 scrydex live 폴백 (칩에만 표시, 히스토리 차트는 없음)
        if (enPsa == null) {
            String enRef = card.getEnScrydexRef();
            if (enRef != null && !enRef.isBlank() && !enRef.startsWith("NO_")) {
                scrydexLiveClient.fetchPrices(enRef, "EN").ifPresent(l ->
                        log.debug("[PriceSummary] enPsa 폴백: card={}", cardId));
                enPsa = scrydexLiveClient.fetchPrices(enRef, "EN")
                        .map(l -> new CardPriceSummaryDto.PsaPrices(l.getPsa10(), l.getPsa9()))
                        .orElse(null);
            }
        }
        if (jpPsa == null) {
            String jpRef = card.getJpScrydexRef();
            if (jpRef != null && !jpRef.isBlank() && !jpRef.startsWith("NO_")) {
                jpPsa = scrydexLiveClient.fetchPrices(jpRef, "JP")
                        .map(l -> new CardPriceSummaryDto.PsaPrices(l.getPsa10(), l.getPsa9()))
                        .orElse(null);
            }
        }

        String confidence = koDomesticCount >= 10 ? "A"
                : koDomesticCount >= 4  ? "B"
                : koDomesticCount >= 1  ? "C" : "D";

        return new CardPriceSummaryDto(
                cardId,
                new CardPriceSummaryDto.KoPrice(
                        koMid, koLow, koHigh, koBasis, confidence,
                        koDomesticCount, LocalDate.now().toString(),
                        PriceLabelType.resolve(promoExclusive, koDomesticCount).name()),
                new CardPriceSummaryDto.Charts(
                        koChart,
                        buildLineChart(enLine, enPsa10Line, enPsa9Line),
                        buildLineChart(jpLine, jpPsa10Line, jpPsa9Line)),
                enPsa,
                jpPsa
        );
    }

    private CardPriceSummaryDto.ChartData buildLineChart(
            List<CardPriceSummaryDto.ChartPoint> line,
            List<CardPriceSummaryDto.ChartPoint> psa10Line,
            List<CardPriceSummaryDto.ChartPoint> psa9Line) {
        if (line.size() < 2) {
            if (psa10Line.size() >= 2 || psa9Line.size() >= 2) {
                return new CardPriceSummaryDto.ChartData("LINE", "OK", line, List.of(), psa10Line, psa9Line);
            }
            return new CardPriceSummaryDto.ChartData("NONE", "INSUFFICIENT_DATA", line, List.of(), psa10Line, psa9Line);
        }
        String reason = isFlatLine(line) ? "FLAT_DATA" : "OK";
        return new CardPriceSummaryDto.ChartData("LINE", reason, line, List.of(), psa10Line, psa9Line);
    }

    /** EN/JP 히스토리 × 비율 → KO 추정선 (JP 우선, EN 보완 — 두 소스 혼합 금지) */
    private List<CardPriceSummaryDto.ChartPoint> buildKoLineFromSnaps(
            List<PriceSnapshot> enSnaps, List<PriceSnapshot> jpSnaps,
            double enRatio, double jpRatio, String rarity, double usdToKrw, double jpyToKrw) {
        Map<LocalDate, PriceSnapshot> enByDate = enSnaps.stream()
                .collect(Collectors.toMap(s -> s.getTradedAt().toLocalDate(), s -> s, (a, b) -> b));
        Map<LocalDate, PriceSnapshot> jpByDate = jpSnaps.stream()
                .collect(Collectors.toMap(s -> s.getTradedAt().toLocalDate(), s -> s, (a, b) -> b));

        TreeMap<LocalDate, Double> byDate = new TreeMap<>();
        Set<LocalDate> dates = new HashSet<>(enByDate.keySet());
        dates.addAll(jpByDate.keySet());

        for (LocalDate date : dates) {
            PriceSnapshot selected = selectScrydexSnapshotForKo(
                    jpByDate.getOrDefault(date, enByDate.get(date)).getCardId(),
                    rarity, jpByDate.get(date), enByDate.get(date), usdToKrw, jpyToKrw, null);
            if (selected == null) continue;
            double ratio = "SCRYDEX_JP".equals(selected.getSource()) ? jpRatio : enRatio;
            byDate.put(date, selected.getPrice() * ratio);
        }

        List<CardPriceSummaryDto.ChartPoint> line = byDate.entrySet().stream()
                .map(e -> new CardPriceSummaryDto.ChartPoint(
                        e.getKey().toString(), (double) Math.round(e.getValue()), null, null))
                .collect(Collectors.toCollection(ArrayList::new));
        return filterJumps(line, 0.35);
    }

    /** 전일 대비 maxRatio 초과 변동 포인트 제거 */
    private List<CardPriceSummaryDto.ChartPoint> filterJumps(
            List<CardPriceSummaryDto.ChartPoint> line, double maxRatio) {
        if (line.size() < 2) return line;
        List<CardPriceSummaryDto.ChartPoint> result = new ArrayList<>();
        result.add(line.get(0));
        for (int i = 1; i < line.size(); i++) {
            double prev = result.get(result.size() - 1).price();
            double curr = line.get(i).price();
            if (prev <= 0 || Math.abs(curr - prev) / prev <= maxRatio) {
                result.add(line.get(i));
            }
        }
        return result;
    }

    private double medianDouble(List<Double> values) {
        List<Double> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        int mid = sorted.size() / 2;
        return sorted.size() % 2 == 0 ? (sorted.get(mid - 1) + sorted.get(mid)) / 2.0 : sorted.get(mid);
    }

    private Integer findClosestPrice(TreeMap<LocalDate, Integer> dateMap, LocalDate target, int maxDays) {
        Map.Entry<LocalDate, Integer> floor = dateMap.floorEntry(target);
        Map.Entry<LocalDate, Integer> ceil  = dateMap.ceilingEntry(target);
        Integer best = null;
        long bestDist = maxDays + 1;
        if (floor != null) {
            long dist = Math.abs(ChronoUnit.DAYS.between(floor.getKey(), target));
            if (dist <= maxDays && dist < bestDist) { bestDist = dist; best = floor.getValue(); }
        }
        if (ceil != null) {
            long dist = Math.abs(ChronoUnit.DAYS.between(ceil.getKey(), target));
            if (dist <= maxDays && dist < bestDist) { best = ceil.getValue(); }
        }
        return best;
    }

    private Map<String, TreeMap<LocalDate, Integer>> groupByCardDate(
            List<PriceSnapshot> snaps, double usdToKrw, double jpyToKrw) {
        Map<String, TreeMap<LocalDate, Integer>> result = new HashMap<>();
        for (PriceSnapshot snap : snaps) {
            result.computeIfAbsent(snap.getCardId(), k -> new TreeMap<>())
                    .put(snap.getTradedAt().toLocalDate(),
                            (int) Math.round(toLatestKrw(snap, usdToKrw, jpyToKrw)));
        }
        return result;
    }

    private void saveRatioCoefficient(String coefCardId, double ratio, LocalDateTime now) {
        boolean exists = priceSnapshotRepository.existsByCardIdAndSourceAndTradedAtAfter(
                coefCardId, COEFF_SOURCE, now.toLocalDate().atStartOfDay());
        if (exists) return;
        priceSnapshotRepository.save(PriceSnapshot.builder()
                .priceSnapshotId(com.fury.back.common.IdGenerator.generate())
                .cardId(coefCardId).source(COEFF_SOURCE)
                .price((int) Math.round(ratio * 10000)).cardStatus("RAW")
                .tradedAt(now).collectedAt(now).build());
    }

    /** EN/JP→KO 비율을 레어도별로 계산해서 DB에 저장 (매일 스케줄러에서 호출) */
    @Transactional
    public void recalculateEnJpRatios() {
        log.info("[EnJpRatio] 계산 시작");
        List<Card> mappedCards = cardRepository.findByRarityCodeInAndLanguage(HIGH_RARE_CODES, "KO")
                .stream()
                .filter(c -> (c.getEnScrydexRef() != null && !c.getEnScrydexRef().startsWith("NO_"))
                          || (c.getJpScrydexRef() != null && !c.getJpScrydexRef().startsWith("NO_")))
                .toList();
        if (mappedCards.isEmpty()) { log.warn("[EnJpRatio] 매핑된 카드 없음"); return; }

        List<String> cardIds = mappedCards.stream().map(Card::getCardId).toList();
        Map<String, String> rarityByCard = mappedCards.stream()
                .collect(Collectors.toMap(Card::getCardId, c -> c.getRarityCode() != null ? c.getRarityCode() : ""));

        LocalDateTime since = LocalDateTime.now().minusDays(180);
        List<PriceSnapshot> naverSnaps = priceSnapshotRepository.findDomesticRawByCardIds(cardIds, since);
        Map<String, List<PriceSnapshot>> naverByCard = naverSnaps.stream()
                .collect(Collectors.groupingBy(PriceSnapshot::getCardId));

        double usdToKrw = exchangeRateClient.getUsdToKrw();
        double jpyToKrw = exchangeRateClient.getJpyToKrw();
        Map<String, TreeMap<LocalDate, Integer>> enByCardDate = groupByCardDate(
                priceSnapshotRepository.findGlobalPrices(cardIds, "SCRYDEX_EN", since), usdToKrw, jpyToKrw);
        Map<String, TreeMap<LocalDate, Integer>> jpByCardDate = groupByCardDate(
                priceSnapshotRepository.findGlobalPrices(cardIds, "SCRYDEX_JP", since), usdToKrw, jpyToKrw);

        Map<String, List<Double>> enByRarity = new HashMap<>();
        Map<String, List<Double>> jpByRarity = new HashMap<>();
        List<Double> enGlobal = new ArrayList<>();
        List<Double> jpGlobal = new ArrayList<>();

        for (Map.Entry<String, List<PriceSnapshot>> entry : naverByCard.entrySet()) {
            String cid = entry.getKey();
            String rar = rarityByCard.getOrDefault(cid, "");
            TreeMap<LocalDate, Integer> enDates = enByCardDate.get(cid);
            TreeMap<LocalDate, Integer> jpDates = jpByCardDate.get(cid);

            for (PriceSnapshot naver : entry.getValue()) {
                LocalDate naverDate = naver.getTradedAt().toLocalDate();
                if (enDates != null) {
                    Integer ep = findClosestPrice(enDates, naverDate, 3);
                    if (ep != null && ep > 0) {
                        double r = naver.getPrice() / (double) ep;
                        if (r >= 0.05 && r <= 5.0) { enByRarity.computeIfAbsent(rar, k -> new ArrayList<>()).add(r); enGlobal.add(r); }
                    }
                }
                if (jpDates != null) {
                    Integer jp = findClosestPrice(jpDates, naverDate, 3);
                    if (jp != null && jp > 0) {
                        double r = naver.getPrice() / (double) jp;
                        if (r >= 0.05 && r <= 5.0) { jpByRarity.computeIfAbsent(rar, k -> new ArrayList<>()).add(r); jpGlobal.add(r); }
                    }
                }
            }
        }

        LocalDateTime now = LocalDateTime.now();
        if (!enGlobal.isEmpty()) saveRatioCoefficient("ko_coef_en_GLOBAL", medianDouble(enGlobal), now);
        if (!jpGlobal.isEmpty()) saveRatioCoefficient("ko_coef_jp_GLOBAL", medianDouble(jpGlobal), now);
        enByRarity.forEach((rar, vals) -> { if (vals.size() >= 5) saveRatioCoefficient("ko_coef_en_" + rar, medianDouble(vals), now); });
        jpByRarity.forEach((rar, vals) -> { if (vals.size() >= 5) saveRatioCoefficient("ko_coef_jp_" + rar, medianDouble(vals), now); });
        log.info("[EnJpRatio] 완료: EN {}건, JP {}건", enGlobal.size(), jpGlobal.size());
    }

    private List<CardPriceSummaryDto.ChartPoint> snapsToPoints(List<PriceSnapshot> snaps, double exchangeRate) {
        double jpyToKrw = exchangeRateClient.getJpyToKrw();
        return snaps.stream()
                .map(s -> {
                    double displayPrice = Math.round(toLatestKrw(s, exchangeRate, jpyToKrw) / exchangeRate * 100.0) / 100.0;
                    Double rawPrice = s.getRawPrice() != null ? s.getRawPrice().doubleValue() : null;
                    return new CardPriceSummaryDto.ChartPoint(
                            s.getTradedAt().toLocalDate().toString(),
                            displayPrice,
                            rawPrice,
                            s.getRawCurrency());
                })
                .toList();
    }

    private List<CardPriceSummaryDto.ChartPoint> psaSnapsToPoints(List<PriceSnapshot> snaps, double exchangeRate) {
        return snapsToPoints(snaps, exchangeRate);
    }

    private CardPriceSummaryDto.PsaPrices extractPsa(
            List<CardPriceSummaryDto.ChartPoint> psa10Line,
            List<CardPriceSummaryDto.ChartPoint> psa9Line) {
        if (psa10Line.isEmpty() && psa9Line.isEmpty()) return null;
        Double psa10 = psa10Line.isEmpty() ? null : psa10Line.get(psa10Line.size() - 1).price();
        Double psa9  = psa9Line.isEmpty()  ? null : psa9Line.get(psa9Line.size() - 1).price();
        return new CardPriceSummaryDto.PsaPrices(psa10, psa9);
    }

    private boolean isFlatLine(List<CardPriceSummaryDto.ChartPoint> line) {
        if (line.size() < 3) return true;
        double min = line.stream().mapToDouble(CardPriceSummaryDto.ChartPoint::price).min().orElse(0);
        double max = line.stream().mapToDouble(CardPriceSummaryDto.ChartPoint::price).max().orElse(0);
        double mid = (min + max) / 2.0;
        if (mid <= 0) return true;
        return (max - min) / mid < 0.02;
    }

    public PriceSnapshot selectScrydexSnapshotForKo(
            String cardId,
            String rarity,
            PriceSnapshot jpSnapshot,
            PriceSnapshot enSnapshot,
            double usdToKrw,
            double jpyToKrw,
            String prevSource) {
        // suspect-first 보존: 이상치 방어가 hysteresis보다 우선
        if (jpSnapshot != null && !isJpRawSuspect(cardId, rarity, jpSnapshot, enSnapshot, usdToKrw, jpyToKrw)) {
            if (enSnapshot != null) {
                double jpKrw = toLatestKrw(jpSnapshot, usdToKrw, jpyToKrw);
                double enKrw = toLatestKrw(enSnapshot, usdToKrw, jpyToKrw);
                double low = Math.min(jpKrw, enKrw);
                double high = Math.max(jpKrw, enKrw);
                // Phase 0+X hysteresis (2026-05-16): prevSource 기준 임계 적용 → source flip oscillation 차단
                double threshold = SPREAD_BASE;
                if ("JP".equals(prevSource)) threshold = SPREAD_TO_EN_FROM_JP;
                else if ("EN".equals(prevSource)) threshold = SPREAD_TO_JP_FROM_EN;
                if (low > 0 && high / low > threshold) {
                    log.warn("[KO-GUARD] cardId={} rarity={} jp={} en={} -> spread={} > threshold={} (prevSource={}), use EN",
                            cardId, rarity, Math.round(jpKrw), Math.round(enKrw),
                            Math.round((high / low) * 10.0) / 10.0, threshold, prevSource);
                    return enSnapshot;
                }
            }
            return jpSnapshot;
        }
        if (jpSnapshot != null && enSnapshot == null) {
            log.warn("[KO-GUARD] cardId={} rarity={} jpRaw={} enRaw=null -> JP suspect, EN fallback unavailable",
                    cardId, rarity, jpRawKrw(jpSnapshot, usdToKrw, jpyToKrw));
        }
        return enSnapshot;
    }

    /**
     * 어제 시점 KO_ESTIMATED가 어떤 source(JP/EN)로 산출됐는지 batch 추정.
     * Phase 0+X hysteresis (2026-05-16) 정책 지원용.
     *
     * 방식: 어제 KO price와 (어제 SCRYDEX × 적용 가능 계수) 비교 → 가까운 쪽이 prevSource.
     * 양쪽 모두 30%+ 차이 → 추정 불가 (map에 없거나 null로 기록).
     *
     * 어제 기준 계수는 RARITY freeze 정책상 현재와 동일하게 사용 (rarityCoeffs/cardCoefs 인자).
     * SCRYDEX raw는 traded_at <= yesterday 기준 staleness 7d 윈도우 latest.
     */
    /**
     * 전일 latest KO_ESTIMATED snapshot의 audit batch 조회.
     * 보완 4 적용: card_id+date 직접 조회 X. snapshot_id 기준 (같은 날 multiple refresh 안전).
     *
     * 1단계: 전일 KO snapshot DISTINCT ON(card_id) latest
     * 2단계: 그 snapshot_id 리스트로 audit batch JOIN
     * 결과: cardId → KoEstimationAudit (audit 없으면 map에 미포함)
     */
    private Map<String, KoEstimationAudit> inferPrevAudits(LocalDate yesterday, Set<String> cardIds) {
        if (cardIds.isEmpty()) return Map.of();

        LocalDateTime yStart = yesterday.atStartOfDay();
        LocalDateTime yEndExclusive = yesterday.plusDays(1).atStartOfDay();

        // 전일 KO snapshot 모두 → DISTINCT ON(card_id) latest 추출
        Map<String, String> cardIdToLatestKoSnapshotId = priceSnapshotRepository
                .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("KO_ESTIMATED", yStart, yEndExclusive)
                .stream()
                .filter(s -> cardIds.contains(s.getCardId()))
                .collect(Collectors.toMap(
                        PriceSnapshot::getCardId,
                        PriceSnapshot::getPriceSnapshotId,
                        (a, b) -> b)); // 같은 카드 multiple row → 마지막(가장 최신) 유지

        if (cardIdToLatestKoSnapshotId.isEmpty()) return Map.of();

        // snapshot_id 기준 audit batch (보완 4)
        Map<String, KoEstimationAudit> auditBySnapshotId = koAuditRepository
                .findByKoSnapshotIdIn(cardIdToLatestKoSnapshotId.values())
                .stream()
                .collect(Collectors.toMap(KoEstimationAudit::getKoSnapshotId, a -> a));

        // cardId → audit map 만들기
        Map<String, KoEstimationAudit> result = new HashMap<>();
        for (Map.Entry<String, String> e : cardIdToLatestKoSnapshotId.entrySet()) {
            KoEstimationAudit audit = auditBySnapshotId.get(e.getValue());
            if (audit != null) result.put(e.getKey(), audit);
        }
        return result;
    }

    // ─────────── Audit helpers (Step B-2) ───────────

    /** %change. prev null/0이면 null. 부호 보존 (curr<prev면 negative). */
    private BigDecimal pctChange(BigDecimal prev, BigDecimal curr) {
        if (prev == null || curr == null || prev.signum() == 0) return null;
        return curr.subtract(prev).multiply(BigDecimal.valueOf(100))
                .divide(prev, 4, java.math.RoundingMode.HALF_UP);
    }

    /** native raw_price 기준 변동 ≥0.5% (currency/source 동일 시만 비교). 보완 1+2 통합. */
    private boolean isRawChangedNative(
            String currSource, String prevSource,
            String currCurrency, String prevCurrency,
            BigDecimal currNative, BigDecimal prevNative) {
        if (prevNative == null || currNative == null || prevNative.signum() == 0) return false;
        if (currSource == null || !currSource.equals(prevSource)) return false;
        if (currCurrency == null || !currCurrency.equals(prevCurrency)) return false;
        BigDecimal diffRatio = currNative.subtract(prevNative).abs()
                .divide(prevNative.abs(), 6, java.math.RoundingMode.HALF_UP);
        return diffRatio.compareTo(BigDecimal.valueOf(0.005)) >= 0;
    }

    /** coef scope/key/value 셋 중 하나라도 다름. 양쪽 모두 null (PROMO_DIRECT)이면 false. */
    private boolean isCoefChanged(
            String prevScope, String prevKey, BigDecimal prevValue,
            String currScope, String currKey, BigDecimal currValue) {
        boolean allNull = prevScope == null && prevKey == null && prevValue == null
                && currScope == null && currKey == null && currValue == null;
        if (allNull) return false;
        if (!java.util.Objects.equals(prevScope, currScope)) return true;
        if (!java.util.Objects.equals(prevKey, currKey)) return true;
        if (prevValue == null && currValue == null) return false;
        if (prevValue == null || currValue == null) return true;
        return prevValue.compareTo(currValue) != 0;
    }

    /** 환율 ≥0.1% 변동 (USD 또는 JPY 어느 하나라도). prev null이면 false. */
    private boolean isExchangeRateChanged(
            BigDecimal prevUsd, BigDecimal currUsd,
            BigDecimal prevJpy, BigDecimal currJpy) {
        BigDecimal threshold = BigDecimal.valueOf(0.001);
        if (prevUsd != null && currUsd != null && prevUsd.signum() != 0) {
            BigDecimal diff = currUsd.subtract(prevUsd).abs()
                    .divide(prevUsd.abs(), 6, java.math.RoundingMode.HALF_UP);
            if (diff.compareTo(threshold) >= 0) return true;
        }
        if (prevJpy != null && currJpy != null && prevJpy.signum() != 0) {
            BigDecimal diff = currJpy.subtract(prevJpy).abs()
                    .divide(prevJpy.abs(), 6, java.math.RoundingMode.HALF_UP);
            if (diff.compareTo(threshold) >= 0) return true;
        }
        return false;
    }

    /** source 비교. 양쪽 null → true (NONE-NONE 동일). 한쪽 null → false. */
    private boolean sameSource(String prevSource, String currSource) {
        if (prevSource == null && currSource == null) return true;
        if (prevSource == null || currSource == null) return false;
        return prevSource.equals(currSource);
    }

    /** 랭킹 후보 source — JP/EN만. PSA10_FALLBACK/PROMO_DIRECT/NONE은 has_ko_trade_change 예외 외엔 제외. */
    private boolean isAllowedRankingSource(String source) {
        return AuditSource.JP.name().equals(source) || AuditSource.EN.name().equals(source);
    }

    /**
     * Large move(>30%) 진위 검증.
     * raw_changed=true + source 동일 + sign 일치 + |ko_pct - raw_pct| ≤ max(5.0, abs(raw_pct)*0.2)면 진짜 시장 변동.
     * raw_change_pct null이면 false (null guard).
     */
    private boolean isLargeMoveValid(
            BigDecimal koChangePct, BigDecimal rawChangePct,
            boolean rawChanged, boolean sourceMatch) {
        if (!rawChanged || !sourceMatch) return false;
        if (koChangePct == null || rawChangePct == null) return false;
        if (koChangePct.signum() != rawChangePct.signum()) return false;
        BigDecimal gap = koChangePct.subtract(rawChangePct).abs();
        BigDecimal threshold = rawChangePct.abs().multiply(BigDecimal.valueOf(0.2))
                .max(BigDecimal.valueOf(5.0));
        return gap.compareTo(threshold) <= 0;
    }

    // ─────────── Step B-3: buildAudit + reason 우선순위 ───────────

    /**
     * KO_ESTIMATED row 1건의 audit row 생성.
     * 모든 비교는 % 단위 (pctChange가 % 단위 반환). 임계: 0.5 / 15.0 / 30.0 / 100 / 5000.
     * 보완 통합: raw_changed=native price 기준, source/coef/fx 분리, is_anomaly와 ranking_eligible 분리.
     */
    private KoEstimationAudit buildAudit(
            String cardId,
            String koSnapshotId,
            java.time.LocalDate estimatedDate,
            int koPrice,
            String selectedSource,
            String selectedRawSnapshotId,
            BigDecimal selectedRawPriceNative,
            String selectedRawCurrency,
            BigDecimal selectedRawPriceKrw,
            LocalDateTime selectedRawTradedAt,
            String coefScope, String coefKey, BigDecimal coefValue,
            BigDecimal usdToKrw, BigDecimal jpyToKrw,
            KoEstimationAudit prevAudit) {

        // prev_* 추출 (prev_audit null이면 모두 null)
        String prevSource = prevAudit == null ? null : prevAudit.getSelectedSource();
        String prevRawSnapId = prevAudit == null ? null : prevAudit.getSelectedRawSnapshotId();
        BigDecimal prevRawNative = prevAudit == null ? null : prevAudit.getSelectedRawPriceNative();
        String prevRawCurrency = prevAudit == null ? null : prevAudit.getSelectedRawCurrency();
        BigDecimal prevRawKrw = prevAudit == null ? null : prevAudit.getSelectedRawPriceKrw();
        LocalDateTime prevRawTradedAt = prevAudit == null ? null : prevAudit.getSelectedRawTradedAt();
        String prevCoefScope = prevAudit == null ? null : prevAudit.getCoefScope();
        String prevCoefKey = prevAudit == null ? null : prevAudit.getCoefKey();
        BigDecimal prevCoefValue = prevAudit == null ? null : prevAudit.getCoefValue();
        BigDecimal prevUsdToKrw = prevAudit == null ? null : prevAudit.getUsdToKrw();
        BigDecimal prevJpyToKrw = prevAudit == null ? null : prevAudit.getJpyToKrw();
        Integer prevKoPrice = prevAudit == null ? null : prevAudit.getKoPrice();

        // Change flags (% 단위 pctChange)
        boolean rawSnapshotChanged = !java.util.Objects.equals(prevRawSnapId, selectedRawSnapshotId);
        boolean rawTimeChanged = !java.util.Objects.equals(prevRawTradedAt, selectedRawTradedAt);
        boolean rawChanged = isRawChangedNative(
                selectedSource, prevSource, selectedRawCurrency, prevRawCurrency,
                selectedRawPriceNative, prevRawNative);
        BigDecimal rawChangePct = pctChange(prevRawNative, selectedRawPriceNative);
        boolean coefChanged = isCoefChanged(
                prevCoefScope, prevCoefKey, prevCoefValue, coefScope, coefKey, coefValue);
        boolean exchangeRateChanged = isExchangeRateChanged(
                prevUsdToKrw, usdToKrw, prevJpyToKrw, jpyToKrw);
        boolean hasKoTradeChange = false; // 1차 false 고정 (NAVER/DAANGN VALID 신규 2차 phase)

        // KO 변화율 (% 단위) — prev_ko_price 기준
        BigDecimal koChangePct = null;
        if (prevKoPrice != null && prevKoPrice > 0) {
            koChangePct = BigDecimal.valueOf(koPrice - prevKoPrice).multiply(BigDecimal.valueOf(100))
                    .divide(BigDecimal.valueOf(prevKoPrice), 4, java.math.RoundingMode.HALF_UP);
        }

        // is_anomaly 판정 — raw로 설명 안 되는 KO 급변
        boolean anomaly = false;
        String anomalyReason = null;
        boolean sourceMatch = sameSource(prevSource, selectedSource);
        if (koChangePct != null) {
            BigDecimal absKoPct = koChangePct.abs();
            // 케이스 1: raw_changed=false + has_ko_trade_change=false + |ko|>=15%
            if (!rawChanged && !hasKoTradeChange
                    && absKoPct.compareTo(BigDecimal.valueOf(15.0)) >= 0) {
                anomaly = true;
                anomalyReason = "KO_MOVE_NO_RAW_EVIDENCE";
            }
            // 케이스 2: large move(>30%) + raw로 설명 안 됨
            if (absKoPct.compareTo(BigDecimal.valueOf(30.0)) > 0
                    && !isLargeMoveValid(koChangePct, rawChangePct, rawChanged, sourceMatch)) {
                anomaly = true;
                anomalyReason = "KO_RAW_MISMATCH";
            }
        }

        // ranking_exclusion_reason 결정 (우선순위)
        String exclusionReason = determineRankingExclusionReason(
                prevAudit, koPrice, prevKoPrice, selectedSource,
                selectedRawPriceNative, prevRawNative,
                rawChanged, coefChanged, exchangeRateChanged, hasKoTradeChange,
                anomaly, koChangePct, rawChangePct, sourceMatch);
        boolean rankingEligible = (exclusionReason == null);

        return KoEstimationAudit.builder()
                .cardId(cardId)
                .koSnapshotId(koSnapshotId)
                .estimatedDate(estimatedDate)
                .koPrice(koPrice)
                .selectedSource(selectedSource)
                .selectedRawSnapshotId(selectedRawSnapshotId)
                .selectedRawPriceNative(selectedRawPriceNative)
                .selectedRawCurrency(selectedRawCurrency)
                .selectedRawPriceKrw(selectedRawPriceKrw)
                .selectedRawTradedAt(selectedRawTradedAt)
                .coefScope(coefScope)
                .coefKey(coefKey)
                .coefValue(coefValue)
                .usdToKrw(usdToKrw)
                .jpyToKrw(jpyToKrw)
                .prevKoSnapshotId(prevAudit == null ? null : prevAudit.getKoSnapshotId())
                .prevSelectedSource(prevSource)
                .prevRawSnapshotId(prevRawSnapId)
                .prevRawPriceNative(prevRawNative)
                .prevRawCurrency(prevRawCurrency)
                .prevRawPriceKrw(prevRawKrw)
                .prevRawTradedAt(prevRawTradedAt)
                .prevCoefScope(prevCoefScope)
                .prevCoefKey(prevCoefKey)
                .prevCoefValue(prevCoefValue)
                .prevUsdToKrw(prevUsdToKrw)
                .prevJpyToKrw(prevJpyToKrw)
                .rawSnapshotChanged(rawSnapshotChanged)
                .rawTimeChanged(rawTimeChanged)
                .rawChanged(rawChanged)
                .rawChangePct(rawChangePct)
                .coefChanged(coefChanged)
                .exchangeRateChanged(exchangeRateChanged)
                .hasKoTradeChange(hasKoTradeChange)
                .anomaly(anomaly)
                .anomalyReason(anomalyReason)
                .rankingEligible(rankingEligible)
                .rankingExclusionReason(exclusionReason)
                .build();
    }

    /**
     * Ranking exclusion reason 우선순위 결정. null 반환 = ranking_eligible=true.
     * 임계 모두 % 단위 (15.0 / 30.0) 또는 원 단위 (5000 / 100).
     */
    private String determineRankingExclusionReason(
            KoEstimationAudit prevAudit,
            int koPrice, Integer prevKoPrice,
            String selectedSource,
            BigDecimal selectedRawPriceNative, BigDecimal prevRawPriceNative,
            boolean rawChanged, boolean coefChanged, boolean exchangeRateChanged,
            boolean hasKoTradeChange, boolean anomaly,
            BigDecimal koChangePct, BigDecimal rawChangePct, boolean sourceMatch) {
        if (prevAudit == null || prevKoPrice == null) return "NO_PREV_AUDIT";
        // FALLBACK_SOURCE를 NO_PREV_AUDIT 직후 2번째로 (2026-05-17 dry-run 검증 결과):
        // PROMO_DIRECT / PSA10_FALLBACK은 구조적으로 랭킹 비허용 source이므로 가격 변동량(LOW/ZERO/MICRO)
        // 과 무관하게 FALLBACK_SOURCE로 일관 분류해야 운영 통계가 흔들리지 않음.
        // is_anomaly boolean과 anomaly_reason은 별도 컬럼으로 그대로 유지.
        if (!isAllowedRankingSource(selectedSource) && !hasKoTradeChange) return "FALLBACK_SOURCE";
        if (koPrice < 5000 || prevKoPrice < 5000) return "LOW_PRICE";
        if (koPrice == prevKoPrice) return "ZERO_CHANGE";
        if (Math.abs(koPrice - prevKoPrice) < 100) return "MICRO_CHANGE";
        if (anomaly) return "ANOMALY";
        if (!sourceMatch) return "SOURCE_CHANGED";
        if (coefChanged) return "COEF_CHANGED";
        if (exchangeRateChanged && !rawChanged && !hasKoTradeChange) return "FX_ONLY_CHANGE";
        if (selectedRawPriceNative == null) return "NO_SELECTED_RAW";
        if (prevRawPriceNative == null) return "NO_PREV_RAW";
        if (!rawChanged && !hasKoTradeChange) return "RAW_UNCHANGED";
        // 30% 초과 라지무브 — anomaly 체크에서 이미 처리됐어야 하지만 안전망
        if (koChangePct != null && koChangePct.abs().compareTo(BigDecimal.valueOf(30.0)) > 0) {
            if (!isLargeMoveValid(koChangePct, rawChangePct, rawChanged, sourceMatch)) {
                return "KO_RAW_MISMATCH";
            }
        }
        return null; // ranking_eligible = true
    }

    private Map<String, String> inferPrevKoSources(
            LocalDate yesterday,
            Set<String> cardIds,
            Map<String, Double> rarityCoeffs,
            Map<String, Map<String, Double>> cardCoefs,
            double usdToKrw,
            double jpyToKrw) {
        if (cardIds.isEmpty()) return Map.of();

        LocalDateTime yStart = yesterday.atStartOfDay();
        LocalDateTime yEndExclusive = yesterday.plusDays(1).atStartOfDay();
        LocalDateTime stalenessStart = yEndExclusive.minusDays(7);

        Map<String, Integer> prevKoMap = priceSnapshotRepository
                .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("KO_ESTIMATED", yStart, yEndExclusive)
                .stream()
                .filter(s -> cardIds.contains(s.getCardId()))
                .collect(Collectors.toMap(PriceSnapshot::getCardId, PriceSnapshot::getPrice, (a, b) -> b));

        Map<String, PriceSnapshot> jpY = priceSnapshotRepository
                .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("SCRYDEX_JP", stalenessStart, yEndExclusive)
                .stream()
                .filter(s -> "RAW".equals(s.getCardStatus()) && cardIds.contains(s.getCardId()))
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> b));
        Map<String, PriceSnapshot> enY = priceSnapshotRepository
                .findBySourceAndTradedAtBetweenOrderByTradedAtAsc("SCRYDEX_EN", stalenessStart, yEndExclusive)
                .stream()
                .filter(s -> "RAW".equals(s.getCardStatus()) && cardIds.contains(s.getCardId()))
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> b));

        Map<String, Card> cardMap = cardRepository.findAllById(cardIds).stream()
                .collect(Collectors.toMap(Card::getCardId, c -> c, (a, b) -> a));

        double globalEnFallback = rarityCoeffs.getOrDefault("en_GLOBAL", 1.0);
        double globalJpFallback = rarityCoeffs.getOrDefault("jp_GLOBAL", 1.0);

        Map<String, String> result = new HashMap<>();
        for (Map.Entry<String, Integer> e : prevKoMap.entrySet()) {
            String cardId = e.getKey();
            int prevKo = e.getValue();
            if (prevKo <= 0) continue;
            Card card = cardMap.get(cardId);
            if (card == null) continue;
            String rarity = card.getRarityCode() != null ? card.getRarityCode() : "";
            String era = resolveEraFromCard(card);

            Map<String, Double> cardCoef = cardCoefs.get(cardId);
            double jpCoef = (cardCoef != null && cardCoef.containsKey("JP")) ? cardCoef.get("JP")
                    : applyEraCap("SCRYDEX_JP", era, rarity,
                            resolveCoeff(rarityCoeffs, "SCRYDEX_JP", era, rarity, globalJpFallback));
            double enCoef = (cardCoef != null && cardCoef.containsKey("EN")) ? cardCoef.get("EN")
                    : applyEraCap("SCRYDEX_EN", era, rarity,
                            resolveCoeff(rarityCoeffs, "SCRYDEX_EN", era, rarity, globalEnFallback));

            PriceSnapshot jpSrc = jpY.get(cardId);
            PriceSnapshot enSrc = enY.get(cardId);
            Double jpEst = (jpSrc != null) ? toLatestKrw(jpSrc, usdToKrw, jpyToKrw) * jpCoef : null;
            Double enEst = (enSrc != null) ? toLatestKrw(enSrc, usdToKrw, jpyToKrw) * enCoef : null;

            double jpDiffRatio = jpEst != null ? Math.abs(prevKo - jpEst) / prevKo : Double.MAX_VALUE;
            double enDiffRatio = enEst != null ? Math.abs(prevKo - enEst) / prevKo : Double.MAX_VALUE;

            // 양쪽 모두 30%+ 차이 → 추정 불가
            if (jpDiffRatio > 0.30 && enDiffRatio > 0.30) continue;
            result.put(cardId, jpDiffRatio <= enDiffRatio ? "JP" : "EN");
        }
        return result;
    }

    private boolean isJpRawSuspect(
            String cardId,
            String rarity,
            PriceSnapshot jpSnapshot,
            PriceSnapshot enSnapshot,
            double usdToKrw,
            double jpyToKrw) {
        if (jpSnapshot == null) return false;

        Double jpRawKrw = rawKrw(jpSnapshot, usdToKrw, jpyToKrw);
        Double enRawKrw = enComparableRawKrw(enSnapshot, usdToKrw, jpyToKrw);
        if (jpRawKrw == null) {
            log.warn("[KO-GUARD] cardId={} rarity={} jpRaw=null enRaw={} -> JP raw_price NULL, fallback to EN",
                    cardId, rarity, enRawKrw);
            return true;
        }

        if (enRawKrw != null && enRawKrw > 0) {
            double ratio = jpRawKrw / enRawKrw;
            if (ratio > JP_EN_RATIO_THRESHOLD) {
                log.warn("[KO-GUARD] cardId={} rarity={} jpRaw={} enRaw={} -> JP/EN ratio={} > threshold={}, fallback to EN",
                        cardId, rarity, Math.round(jpRawKrw), Math.round(enRawKrw),
                        Math.round(ratio * 10.0) / 10.0, JP_EN_RATIO_THRESHOLD);
                return true;
            }
        }

        int cap = jpRawCapKrw(rarity);
        if (jpRawKrw > cap) {
            log.warn("[KO-GUARD] cardId={} rarity={} jpRaw={} cap={} -> JP raw exceeds rarity cap, fallback to EN",
                    cardId, rarity, Math.round(jpRawKrw), cap);
            return true;
        }

        // PSA10 정렬 가드는 batch 버전으로 재작성 예정 (N+1 query 회피)
        return false;
    }

    private Double rawKrw(PriceSnapshot snapshot, double usdToKrw, double jpyToKrw) {
        if (snapshot == null) return null;
        if (snapshot.getRawPrice() == null || snapshot.getRawCurrency() == null) {
            // Fallback: stored price is already KRW
            return snapshot.getPrice() != null ? (double) snapshot.getPrice() : null;
        }
        return switch (snapshot.getRawCurrency()) {
            case "USD" -> snapshot.getRawPrice().doubleValue() * usdToKrw;
            case "JPY" -> snapshot.getRawPrice().doubleValue() * jpyToKrw;
            case "KRW" -> snapshot.getRawPrice().doubleValue();
            default -> null;
        };
    }

    private Double enComparableRawKrw(PriceSnapshot snapshot, double usdToKrw, double jpyToKrw) {
        Double raw = rawKrw(snapshot, usdToKrw, jpyToKrw);
        if (raw != null) return raw;
        return snapshot != null && snapshot.getPrice() != null ? snapshot.getPrice().doubleValue() : null;
    }

    private Double jpRawKrw(PriceSnapshot snapshot, double usdToKrw, double jpyToKrw) {
        return rawKrw(snapshot, usdToKrw, jpyToKrw);
    }

    private int jpRawCapKrw(String rarity) {
        return JP_RAW_RARITY_CAPS_KRW.getOrDefault(rarity, JP_RAW_GLOBAL_CAP_KRW);
    }

    private double toLatestKrw(PriceSnapshot snapshot, double usdToKrw, double jpyToKrw) {
        if (snapshot.getRawPrice() == null || snapshot.getRawCurrency() == null) {
            return snapshot.getPrice();
        }
        return switch (snapshot.getRawCurrency()) {
            case "USD" -> snapshot.getRawPrice().doubleValue() * usdToKrw;
            case "JPY" -> snapshot.getRawPrice().doubleValue() * jpyToKrw;
            default -> snapshot.getPrice();
        };
    }

    private int roundPrice(int value) {
        if (value >= 100000) return (value / 10000) * 10000;
        if (value >= 10000)  return (value / 1000)  * 1000;
        return (value / 100) * 100;
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

    /**
     * buildKoEstimatedSnapshots 반환 — KO 스냅샷 + 카드별 선택 source + audit rows.
     * backfill에서 다음 날짜의 prevSource로 carry 가능 (hysteresis 정책).
     * audits는 buildKoEstimatedSnapshotsWithAudit 사용 시 채워짐. 기존 buildKo는 List.of().
     */
    public record BuildKoResult(
        List<PriceSnapshot> snapshots,
        Map<String, String> selectedSourceByCard,
        List<KoEstimationAudit> audits
    ) {}
}
