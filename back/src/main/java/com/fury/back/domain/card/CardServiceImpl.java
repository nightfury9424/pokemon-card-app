package com.fury.back.domain.card;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.dto.CardDto;
import com.fury.back.domain.card.dto.CardSearchDto;
import com.fury.back.domain.interest.CardInterestRepository;
import com.fury.back.domain.price.CoefficientCache;
import com.fury.back.domain.price.ExchangeRateClient;
import com.fury.back.domain.price.GlobalPriceService;
import com.fury.back.domain.price.PriceSnapshot;
import com.fury.back.domain.price.PriceSnapshotRepository;
import com.fury.back.domain.price.dto.MarketCoefficientDto;
import com.fury.back.domain.product.ProductRepository;
import com.fury.back.domain.trade.BuyOrderRepository;
import com.fury.back.domain.trade.TradePostRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import org.springframework.beans.factory.annotation.Value;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Duration;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.stream.Collectors;

@Slf4j
@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class CardServiceImpl implements CardService {

    private final CardRepository cardRepository;
    private final ProductRepository productRepository;
    private final PriceSnapshotRepository priceSnapshotRepository;
    private final CoefficientCache coefficientCache;
    private final GlobalPriceService globalPriceService;
    private final ExchangeRateClient exchangeRateClient;
    private final com.fury.back.domain.price.RawPsa10RatioCalculator rawPsa10RatioCalculator;
    // Phase 1 — 거래 리스트 row engagement 카운트(매도/매수/관심) batch enrichment 용.
    private final TradePostRepository tradePostRepository;
    private final BuyOrderRepository buyOrderRepository;
    private final CardInterestRepository cardInterestRepository;

    private static final Duration MARKET_COUNT_CACHE_TTL = Duration.ofMinutes(5);
    private final Map<String, CountCacheEntry> marketCountCache = new ConcurrentHashMap<>();

    @Value("${card.image.dir}")
    private String cardImageDir;

    private static final String SCRYDEX_CDN = "https://images.scrydex.com/pokemon/%s/medium";
    private final HttpClient httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();

    @Override
    @Transactional
    public Map<String, Object> addCard(AddCardRequest request) {
        if (request == null) throw new IllegalArgumentException("요청 본문은 필수입니다.");
        if (request.name() == null || request.name().isBlank()) throw new IllegalArgumentException("name은 필수입니다.");

        String enRef = blankToNull(request.enScrydexRef());
        String jpRef = blankToNull(request.jpScrydexRef());
        if (enRef == null && jpRef == null && blankToNull(request.koCardCode()) == null) {
            throw new IllegalArgumentException("enScrydexRef, jpScrydexRef, koCardCode 중 하나 이상 필요합니다.");
        }

        // productId 자동 결정
        String productId = blankToNull(request.productId());
        if (productId == null) {
            if (jpRef != null && enRef == null) productId = "JP_PROMO_EXCLUSIVE";
            else if (enRef != null && jpRef == null) productId = "EN_PROMO_EXCLUSIVE";
            else productId = "FOREIGN_ONLY";
        }

        // language 자동 결정
        String language = blankToNull(request.language());
        if (language == null) {
            boolean hasKo = blankToNull(request.koCardCode()) != null || blankToNull(request.productId()) != null;
            if (hasKo) language = "KO";
            else if (jpRef != null && enRef != null) language = "MULTI";
            else if (jpRef != null) language = "JP";
            else language = "EN";
        }

        Card card = Card.builder()
                .cardId(generateCardId())
                .productId(productId)
                .name(request.name())
                .collectionNumber(blankToNull(request.collectionNumber()))
                .rarityCode(blankToNull(request.rarityCode()))
                .language(language)
                .superType("POKEMON")
                .enScrydexRef(enRef)
                .jpScrydexRef(jpRef)
                .build();
        Card saved = cardRepository.save(card);
        String cardId = saved.getCardId();

        // 트랜잭션 커밋 후 외부 호출 (HTTP + 파일 I/O는 트랜잭션 밖에서)
        Map<String, Object> priceFetch = globalPriceService.triggerPriceFetchForCard(cardId);
        List<String> downloadedImages = downloadImagesAfterCommit(cardId, enRef, jpRef);

        return Map.of(
                "cardId", cardId,
                "name", saved.getName(),
                "rarityCode", saved.getRarityCode() == null ? "" : saved.getRarityCode(),
                "productId", saved.getProductId(),
                "collectionNumber", saved.getCollectionNumber() == null ? "" : saved.getCollectionNumber(),
                "enScrydexRef", saved.getEnScrydexRef() == null ? "" : saved.getEnScrydexRef(),
                "jpScrydexRef", saved.getJpScrydexRef() == null ? "" : saved.getJpScrydexRef(),
                "images", downloadedImages,
                "priceFetch", priceFetch);
    }

    // @Transactional 없음 — 파일 I/O + DB update를 트랜잭션 밖에서 처리
    private List<String> downloadImagesAfterCommit(String cardId, String jpRef, String enRef) {
        List<String> saved = new ArrayList<>();
        downloadImage(cardId, jpRef, "jp").ifPresent(saved::add);
        downloadImage(cardId, enRef, "en").ifPresent(saved::add);
        if (!saved.isEmpty()) {
            cardRepository.findById(cardId).ifPresent(c -> {
                c.updateLocalImagePath(saved.get(0));
                cardRepository.save(c);
            });
        }
        return saved;
    }

    private List<String> downloadImages(Card card) {
        List<String> saved = new ArrayList<>();
        downloadImage(card.getCardId(), card.getJpScrydexRef(), "jp").ifPresent(saved::add);
        downloadImage(card.getCardId(), card.getEnScrydexRef(), "en").ifPresent(saved::add);
        return saved;
    }

    private Optional<String> downloadImage(String cardId, String ref, String lang) {
        if (ref == null || ref.isBlank() || ref.startsWith("NO_")) return Optional.empty();
        try {
            String url = String.format(SCRYDEX_CDN, ref);
            HttpRequest req = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(10))
                    .header("User-Agent", "Mozilla/5.0")
                    .GET().build();
            HttpResponse<byte[]> res = httpClient.send(req, HttpResponse.BodyHandlers.ofByteArray());
            if (res.statusCode() != 200) return Optional.empty();
            Path dir = Paths.get(cardImageDir);
            Files.createDirectories(dir);
            Path imgPath = dir.resolve(cardId + "_" + lang + ".png");
            Files.write(imgPath, res.body());
            return Optional.of(imgPath.toString());
        } catch (Exception e) {
            log.warn("이미지 다운로드 실패: cardId={}, ref={}, err={}", cardId, ref, e.getMessage());
            return Optional.empty();
        }
    }

    private String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    private String generateCardId() {
        return "CRD_" + UUID.randomUUID().toString().replace("-", "").toUpperCase();
    }

    @Override
    public ReturnData<CardDto> getCard(String cardId) {
        if (cardId == null || cardId.isBlank()) {
            return ReturnData.badRequest("cardId는 필수입니다.");
        }
        Optional<Card> card = cardRepository.findById(cardId);
        return card.<ReturnData<CardDto>>map(c -> {
            var product = productRepository.findById(c.getProductId()).orElse(null);
            return ReturnData.success(CardDto.from(c, product));
        }).orElseGet(() -> ReturnData.notFound("카드를 찾을 수 없습니다. cardId=" + cardId));
    }

    @Override
    public ReturnData<CardDto> getCardWithPrice(String cardId) {
        if (cardId == null || cardId.isBlank()) {
            return ReturnData.badRequest("cardId는 필수입니다.");
        }
        Optional<Card> cardOpt = cardRepository.findById(cardId);
        if (cardOpt.isEmpty()) {
            return ReturnData.notFound("카드를 찾을 수 없습니다. cardId=" + cardId);
        }
        Card card = cardOpt.get();
        var product = productRepository.findById(card.getProductId()).orElse(null);
        CardDto base = CardDto.from(card, product);

        // KO 가격 / 변동률 enrich — buildNativeResult와 동일 패턴, 단일 카드용
        List<String> ids = List.of(cardId);
        Map<String, PriceSnapshot> snapshotsBySource = priceSnapshotRepository
                .findLatestMarketSnapshotsByCardIds(ids)
                .stream()
                .collect(Collectors.toMap(PriceSnapshot::getSource, s -> s, (a, b) -> a));
        PriceSnapshot koEst = snapshotsBySource.get("KO_ESTIMATED");
        PriceSnapshot jpSnap = snapshotsBySource.get("SCRYDEX_JP");
        PriceSnapshot enSnap = snapshotsBySource.get("SCRYDEX_EN");

        Integer ko = null;
        String koBasis = null;

        if (card.isPromoExclusive()) {
            PriceSnapshot jpPsa10 = null;
            if (jpSnap == null) {
                jpPsa10 = priceSnapshotRepository.findLatestScrydexJpPsa10ByCardIds(ids)
                        .stream().findFirst().orElse(null);
            }
            if (jpSnap != null) {
                ko = jpSnap.getPrice();
                koBasis = "RAW";
            } else if (jpPsa10 != null) {
                // PSA10만 있는 케이스 — 평균 ratio + coeff로 추정하면 인기 한정판 카드의
                // 실제 시세와 큰 괴리(자산 평가 60~80% 과소평가). 데이터 보강(KREAM 한국
                // 거래가) 전까지는 PSA10 가격 그대로 표시 (참고가). RAW_FROM_PSA10 분기
                // 비활성. derivedKoFromJpPsa10()는 시스템에 남아있어 ratio 데이터는 계속
                // 수집됨 (Admin 페이지에서 모니터링).
                ko = jpPsa10.getPrice();
                koBasis = "PSA10";
            } else if (enSnap != null) {
                ko = enSnap.getPrice();
                koBasis = "RAW";
            }
        } else if (koEst != null) {
            // KO_ESTIMATED DB 저장값 우선 (배치 결과 재사용)
            ko = koEst.getPrice();
        } else {
            // live fallback — 레어도별 계수 + 환율로 SCRYDEX_JP/EN에서 KO 계산
            MarketCoefficientDto coeff = coefficientCache.getOrNull();
            double globalCoeff = coeff != null ? coeff.getCoefficient() : 1.0;
            double usdToKrw = coeff != null ? coeff.getExchangeRate() : 1450.0;
            double jpyToKrw = exchangeRateClient.getJpyToKrw();
            String rarity = card.getRarityCode() != null ? card.getRarityCode() : "";
            String era = globalPriceService.resolveEra(card.getOfficialCardCode());

            Map<String, Double> allCoeffs = priceSnapshotRepository.findAllRarityCoefficients().stream()
                    .collect(Collectors.toMap(
                            s -> s.getCardId().replace("ko_coef_", ""),
                            s -> s.getPrice() / 10000.0,
                            (a, b) -> a));
            double enRatio = globalPriceService.applyEraCap("SCRYDEX_EN", era, rarity,
                    globalPriceService.resolveCoeff(allCoeffs, "SCRYDEX_EN", era, rarity, globalCoeff));
            double jpRatio = globalPriceService.applyEraCap("SCRYDEX_JP", era, rarity,
                    globalPriceService.resolveCoeff(allCoeffs, "SCRYDEX_JP", era, rarity, globalCoeff));

            PriceSnapshot src = globalPriceService.selectScrydexSnapshotForKo(
                    cardId, rarity, jpSnap, enSnap, usdToKrw, jpyToKrw, null);
            if (src != null) {
                double ratio = "SCRYDEX_JP".equals(src.getSource()) ? jpRatio : enRatio;
                ko = (int) Math.round(src.getPrice() * ratio);
            }
        }

        Integer yesterdayPrice = null;
        Double gainPct = null;
        List<Object[]> dailyRows = cardRepository.findKoDailyChangeByCardIds(ids);
        if (!dailyRows.isEmpty()) {
            Object[] row = dailyRows.get(0);
            yesterdayPrice = row[2] == null ? null : ((Number) row[2]).intValue();
            gainPct = row[3] == null ? null : ((Number) row[3]).doubleValue();
        }

        var builder = base.toBuilder();
        if (ko != null) {
            builder.koEstimatedPrice(ko);
            if (koBasis != null) builder.koPriceBasis(koBasis);
        }
        if (yesterdayPrice != null) builder.yesterdayPrice(yesterdayPrice);
        if (gainPct != null) builder.gainPct(gainPct);
        return ReturnData.success(builder.build());
    }

    @Override
    public ReturnData<List<CardSearchDto>> searchCards(String name) {
        if (name == null || name.isBlank()) {
            return ReturnData.badRequest("name은 필수입니다.");
        }
        List<CardSearchDto> result = cardRepository.findByNameContainingIgnoreCase(name)
                .stream()
                .map(CardSearchDto::from)
                .toList();
        return ReturnData.success(result);
    }

    @Override
    public ReturnData<List<CardSearchDto>> searchCards(String name, String language) {
        if (name == null || name.isBlank()) {
            return ReturnData.badRequest("name은 필수입니다.");
        }
        if (language == null || language.isBlank()) {
            return searchCards(name);
        }
        List<CardSearchDto> result = cardRepository
                .findByNameContainingIgnoreCaseAndLanguage(name, language.toUpperCase())
                .stream()
                .map(CardSearchDto::from)
                .toList();
        return ReturnData.success(result);
    }

    @Override
    public ReturnData<CardDto> getCardByCode(String officialCardCode) {
        if (officialCardCode == null || officialCardCode.isBlank()) {
            return ReturnData.badRequest("officialCardCode는 필수입니다.");
        }
        Optional<Card> card = cardRepository.findByOfficialCardCode(officialCardCode);
        return card.<ReturnData<CardDto>>map(c -> ReturnData.success(CardDto.from(c)))
                .orElseGet(() -> ReturnData.notFound("카드를 찾을 수 없습니다. code=" + officialCardCode));
    }

    @Override
    public Map<String, Object> getCardsByRarity(List<String> rarityCodes, Pageable pageable) {
        Page<Card> page = cardRepository.findByRarityCodeInAndLanguageOrderByNameAsc(rarityCodes, "KO", pageable);
        return buildMarketResult(page);
    }

    @Override
    public Map<String, Object> searchCardsByNameAndRarity(String name, List<String> rarityCodes, Pageable pageable) {
        Page<Card> page = cardRepository.findByNameContainingIgnoreCaseAndRarityCodeInAndLanguageOrderByNameAsc(
                name, rarityCodes, "KO", pageable);
        return buildMarketResult(page);
    }

    private Map<String, Object> buildMarketResult(Page<Card> page) {
        var cards = page.getContent();
        return buildNativeResult(cards, page.getTotalElements(), page.getSize(), page.getNumber());
    }

    @Override
    public Map<String, Object> getCardsByRarityOrderByPrice(List<String> rarityCodes, String name, int size, int offset) {
        List<Card> cards = cardRepository.findByRarityOrderByLatestPriceDesc(rarityCodes, name, size, offset);
        long total = getCachedMarketCount(rarityCodes, name);
        return buildNativeResult(cards, total, size, offset / size);
    }

    @Override
    public Map<String, Object> getMarketCards(List<String> rarityCodes, String name, int page, int size, String sortBy, String sortDir) {
        int offset = page * size;
        boolean asc = !"desc".equalsIgnoreCase(sortDir);
        long total = getCachedMarketCount(rarityCodes, name);

        List<Card> cards = switch (sortBy) {
            case "price"  -> asc
                    ? cardRepository.findByRarityOrderByLatestPriceAsc(rarityCodes, name, size, offset)
                    : cardRepository.findByRarityOrderByLatestPriceDesc(rarityCodes, name, size, offset);
            case "rarity" -> asc
                    ? cardRepository.findByRarityOrderByRarityAsc(rarityCodes, name, size, offset)
                    : cardRepository.findByRarityOrderByRarityDesc(rarityCodes, name, size, offset);
            case "date"   -> asc
                    ? cardRepository.findByRarityOrderByLatestDateAsc(rarityCodes, name, size, offset)
                    : cardRepository.findByRarityOrderByLatestDateDesc(rarityCodes, name, size, offset);
            default       -> asc
                    ? cardRepository.findByRarityOrderByNameAsc(rarityCodes, name, size, offset)
                    : cardRepository.findByRarityOrderByNameDesc(rarityCodes, name, size, offset);
        };

        return buildNativeResult(cards, total, size, page);
    }

    @Override
    public List<CardDto> getTopGainerCards(int size) {
        return mapGainerRows(cardRepository.findTopGainersByKoEstimatedPrice(clamp(size)));
    }

    @Override
    public List<CardDto> getTopLoserCards(int size) {
        return mapGainerRows(cardRepository.findTopLosersByKoEstimatedPrice(clamp(size)));
    }

    @Override
    public List<CardDto> getRecentGainerCards(int days, int size) {
        return mapRecentRows(cardRepository.findRecentGainersByKoEstimatedPrice(
                clampDays(days), clampRecent(size)));
    }

    @Override
    public List<CardDto> getRecentLoserCards(int days, int size) {
        return mapRecentRows(cardRepository.findRecentLosersByKoEstimatedPrice(
                clampDays(days), clampRecent(size)));
    }

    /**
     * Turn D-3 (2026-05-17): recent ranking 전용 mapper.
     * 7 col: cardId, currentPrice, moveDatePrice, prevPrice, changeAmount, changePct, moveDate
     * 기존 mapGainerRows(4 col) 영향 0 — 별도 메서드로 분리.
     */
    private List<CardDto> mapRecentRows(List<Object[]> rows) {
        if (rows.isEmpty()) return List.of();
        record RecentRow(int currentPrice, int moveDatePrice, int prevPrice,
                         int changeAmount, double changePct, java.time.LocalDate moveDate) {}
        Map<String, RecentRow> infoByCardId = new LinkedHashMap<>();
        for (Object[] row : rows) {
            String cardId = (String) row[0];
            int currentPrice = row[1] == null ? 0 : ((Number) row[1]).intValue();
            int moveDatePrice = row[2] == null ? 0 : ((Number) row[2]).intValue();
            int prevPrice = row[3] == null ? 0 : ((Number) row[3]).intValue();
            int changeAmount = row[4] == null ? 0 : ((Number) row[4]).intValue();
            double changePct = row[5] == null ? 0.0 : ((Number) row[5]).doubleValue();
            java.time.LocalDate moveDate = row[6] == null ? null
                    : (row[6] instanceof java.sql.Date sqlDate
                        ? sqlDate.toLocalDate()
                        : (java.time.LocalDate) row[6]);
            infoByCardId.put(cardId, new RecentRow(
                    currentPrice, moveDatePrice, prevPrice, changeAmount, changePct, moveDate));
        }
        Map<String, Card> cardsById = cardRepository.findAllById(infoByCardId.keySet())
                .stream()
                .collect(Collectors.toMap(Card::getCardId, card -> card));
        return enrichEngagementCounts(infoByCardId.entrySet().stream()
                .map(entry -> {
                    Card card = cardsById.get(entry.getKey());
                    if (card == null) return null;
                    RecentRow info = entry.getValue();
                    return CardDto.from(card).toBuilder()
                            .currentPrice(info.currentPrice())
                            .moveDatePrice(info.moveDatePrice())
                            .prevPrice(info.prevPrice())
                            .changeAmount(info.changeAmount())
                            .gainPct(info.changePct())
                            .moveDate(info.moveDate())
                            // 기존 필드 호환 — koEstimatedPrice = currentPrice (앱 가격 표시 일관성)
                            .koEstimatedPrice(info.currentPrice())
                            .latestPrice(info.currentPrice())
                            .build();
                })
                .filter(java.util.Objects::nonNull)
                .toList());
    }

    private int clampDays(int days) {
        return Math.max(1, Math.min(days, 30));
    }

    private int clampRecent(int size) {
        return Math.max(1, Math.min(size, 200));
    }

    @Override
    public List<CardDto> getPopularCards(int size) {
        // findPopular row 형식: (card_id, today_price, yesterday_price, gain_pct, interest_count)
        // gain_pct까지 mapGainerRows와 동일하게 처리하고 interest_count는 일단 무시 (정렬은 SQL이 처리).
        return mapGainerRows(cardRepository.findPopularByInterestCount(clamp(size)));
    }

    private int clamp(int size) {
        return Math.max(1, Math.min(size, 50));
    }

    /**
     * Phase 1 — 거래 리스트 row에 매도/매수/관심 카운트를 batch query 3개로 enrich.
     * mapGainerRows, mapRecentRows, buildNativeResult 끝에서 호출. 정렬·페이징 무관 (read-only aggregate).
     * 응답 contract = ADD-ONLY (CardDto에 필드 3개 추가). 가격값 변경 0.
     */
    private List<CardDto> enrichEngagementCounts(List<CardDto> dtos) {
        if (dtos == null || dtos.isEmpty()) return dtos;
        List<String> cardIds = dtos.stream()
                .map(CardDto::getCardId)
                .filter(java.util.Objects::nonNull)
                .toList();
        if (cardIds.isEmpty()) return dtos;
        Map<String, Integer> sellCounts = aggregateCounts(tradePostRepository.countActiveByCardIds(cardIds));
        Map<String, Integer> buyCounts = aggregateCounts(buyOrderRepository.countOpenByCardIds(cardIds));
        Map<String, Integer> interestCounts = aggregateCounts(cardInterestRepository.countByCardIds(cardIds));
        return dtos.stream()
                .map(dto -> dto.toBuilder()
                        .activeSellCount(sellCounts.getOrDefault(dto.getCardId(), 0))
                        .activeBuyCount(buyCounts.getOrDefault(dto.getCardId(), 0))
                        .interestCount(interestCounts.getOrDefault(dto.getCardId(), 0))
                        .build())
                .toList();
    }

    private Map<String, Integer> aggregateCounts(List<Object[]> rows) {
        return rows.stream().collect(Collectors.toMap(
                r -> (String) r[0],
                r -> ((Number) r[1]).intValue(),
                (a, b) -> a));
    }

    private List<CardDto> mapGainerRows(List<Object[]> rows) {
        if (rows.isEmpty()) return List.of();
        record GainRow(int today, int yesterday, double pct) {}
        Map<String, GainRow> infoByCardId = new LinkedHashMap<>();
        for (Object[] row : rows) {
            String cardId = (String) row[0];
            int today = row[1] == null ? 0 : ((Number) row[1]).intValue();
            int yesterday = row[2] == null ? 0 : ((Number) row[2]).intValue();
            double pct = row[3] == null ? 0.0 : ((Number) row[3]).doubleValue();
            infoByCardId.put(cardId, new GainRow(today, yesterday, pct));
        }
        Map<String, Card> cardsById = cardRepository.findAllById(infoByCardId.keySet())
                .stream()
                .collect(Collectors.toMap(Card::getCardId, card -> card));
        return enrichEngagementCounts(infoByCardId.entrySet().stream()
                .map(entry -> {
                    Card card = cardsById.get(entry.getKey());
                    if (card == null) return null;
                    GainRow info = entry.getValue();
                    return CardDto.from(card).toBuilder()
                            .latestPrice(info.today())
                            .koEstimatedPrice(info.today())
                            .yesterdayPrice(info.yesterday())
                            .gainPct(info.pct())
                            .build();
                })
                .filter(java.util.Objects::nonNull)
                .toList());
    }

    private long getCachedMarketCount(List<String> rarityCodes, String name) {
        String normalizedName = name == null ? "" : name.trim();
        String cacheKey = normalizedName + "|" + rarityCodes.stream().sorted().collect(Collectors.joining(","));
        long now = System.nanoTime();
        CountCacheEntry cached = marketCountCache.get(cacheKey);
        if (cached != null && now - cached.createdAtNanos() < MARKET_COUNT_CACHE_TTL.toNanos()) {
            return cached.total();
        }

        long total = cardRepository.countByRarityAndName(rarityCodes, normalizedName);
        marketCountCache.put(cacheKey, new CountCacheEntry(total, now));
        return total;
    }

    @Override
    public Map<String, Object> getPromoCards(String name, int page, int size) {
        int offset = page * size;
        long total = cardRepository.countPromoExclusive(name);
        List<Card> cards = cardRepository.findPromoExclusiveOrderByPriceDesc(name, size, offset);
        return buildNativeResult(cards, total, size, page);
    }

    private Map<String, Object> buildNativeResult(List<Card> cards, long total, int size, int page) {
        var cardIds = cards.stream().map(Card::getCardId).toList();
        if (cardIds.isEmpty()) {
            return Map.of("content", List.of(), "totalElements", total,
                    "totalPages", (int) Math.ceil((double) total / size), "page", page);
        }

        // formulaPrice 소스: SCRYDEX_JP × JP계수 우선, 없으면 SCRYDEX_EN × EN계수
        Map<String, Map<String, PriceSnapshot>> latestMarketSnapshots = priceSnapshotRepository
                .findLatestMarketSnapshotsByCardIds(cardIds)
                .stream()
                .collect(Collectors.groupingBy(
                        PriceSnapshot::getCardId,
                        Collectors.toMap(PriceSnapshot::getSource, s -> s, (a, b) -> a)));
        // scrydex RAW가 없는 카드도 기존 배치 저장값을 보여줄 수 있도록 KO_ESTIMATED를 fallback으로 유지한다.
        Map<String, PriceSnapshot> koEstMap = snapshotsBySource(latestMarketSnapshots, "KO_ESTIMATED");
        Map<String, PriceSnapshot> scrydexEnMap = snapshotsBySource(latestMarketSnapshots, "SCRYDEX_EN");
        Map<String, PriceSnapshot> scrydexJpMap = snapshotsBySource(latestMarketSnapshots, "SCRYDEX_JP");
        // 프로모 카드 중 RAW JP가 없는 경우 PSA10 최신가로 보완
        Map<String, PriceSnapshot> scrydexJpPsa10Map = priceSnapshotRepository
                .findLatestScrydexJpPsa10ByCardIds(cardIds)
                .stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));

        // 4차-Round3: 카드별 변동률 (어제 KO_EST vs 오늘 KO_EST). 모든 시장 카드에 표시.
        Map<String, double[]> dailyChangeMap = new java.util.HashMap<>();
        for (Object[] row : cardRepository.findKoDailyChangeByCardIds(cardIds)) {
            String cid = (String) row[0];
            int yesterday = ((Number) row[2]).intValue();
            double pct = ((Number) row[3]).doubleValue();
            dailyChangeMap.put(cid, new double[]{yesterday, pct});
        }

        MarketCoefficientDto coeff = coefficientCache.getOrNull();
        double globalCoeff = coeff != null ? coeff.getCoefficient() : 1.0;
        double usdToKrw = coeff != null ? coeff.getExchangeRate() : 1450.0;
        double jpyToKrw = exchangeRateClient.getJpyToKrw();

        // 레어도별 계수 로드 (detail 화면과 동일 로직)
        Map<String, Double> allCoeffs = priceSnapshotRepository.findAllRarityCoefficients().stream()
                .collect(java.util.stream.Collectors.toMap(
                        s -> s.getCardId().replace("ko_coef_", ""),
                        s -> s.getPrice() / 10000.0,
                        (a, b) -> a));
        Map<String, String> rarityByCard = cards.stream()
                .collect(Collectors.toMap(Card::getCardId,
                        c -> c.getRarityCode() != null ? c.getRarityCode() : ""));

        // Phase 1 — content list 빌드 후 enrich (매도/매수/관심 카운트). 인라인으로 enrich
        // 못 박으므로 List<CardDto> 변수로 받아서 처리.
        List<CardDto> content = cards.stream()
                        .map(c -> {
                            String cid = c.getCardId();
                            PriceSnapshot dtoSnap = scrydexJpMap.containsKey(cid)
                                    ? scrydexJpMap.get(cid) : scrydexEnMap.get(cid);
                            if (c.isPromoExclusive()) {
                                dtoSnap = scrydexJpMap.containsKey(cid)
                                        ? scrydexJpMap.get(cid) : scrydexEnMap.get(cid);
                            }
                            CardDto dto = CardDto.fromWithPrice(c, dtoSnap);

                            // 카드별 레어도 비율 (detail 화면과 동일)
                            String rarity = rarityByCard.getOrDefault(cid, "");
                            String era = globalPriceService.resolveEra(c.getOfficialCardCode());
                            double enRatio = globalPriceService.applyEraCap("SCRYDEX_EN", era, rarity,
                                    globalPriceService.resolveCoeff(
                                            allCoeffs, "SCRYDEX_EN", era, rarity, globalCoeff));
                            double jpRatio = globalPriceService.applyEraCap("SCRYDEX_JP", era, rarity,
                                    globalPriceService.resolveCoeff(
                                            allCoeffs, "SCRYDEX_JP", era, rarity, globalCoeff));

                            PriceSnapshot jpSnap = scrydexJpMap.get(cid);
                            boolean jpIsPsa10 = false;
                            if (jpSnap == null && c.isPromoExclusive()) {
                                jpSnap = scrydexJpPsa10Map.get(cid);
                                jpIsPsa10 = (jpSnap != null);
                            }
                            PriceSnapshot enSnap = scrydexEnMap.get(cid);
                            Integer ko;
                            String koBasis = null;

                            if (c.isPromoExclusive()) {
                                if (jpSnap != null) {
                                    ko = jpSnap.getPrice();
                                    koBasis = jpIsPsa10 ? "PSA10" : "RAW";
                                } else if (enSnap != null) {
                                    ko = enSnap.getPrice();
                                    koBasis = "RAW";
                                } else {
                                    ko = null;
                                }
                            } else {
                                // KO_ESTIMATED DB 저장값 우선 — 없으면 live 계산 fallback
                                PriceSnapshot koEst = koEstMap.get(cid);
                                if (koEst != null) {
                                    ko = koEst.getPrice();
                                } else {
                                    PriceSnapshot src = globalPriceService.selectScrydexSnapshotForKo(
                                            cid, rarity, jpSnap, enSnap, usdToKrw, jpyToKrw, null);
                                    if (src != null) {
                                        double ratio = "SCRYDEX_JP".equals(src.getSource()) ? jpRatio : enRatio;
                                        ko = (int) Math.round(src.getPrice() * ratio);
                                    } else {
                                        ko = null;
                                    }
                                }
                            }

                            if (ko != null) {
                                dto = dto.toBuilder().koEstimatedPrice(ko).koPriceBasis(koBasis).build();
                            }
                            // 카드별 변동률 (yesterday + gainPct)
                            double[] daily = dailyChangeMap.get(cid);
                            if (daily != null) {
                                dto = dto.toBuilder()
                                        .yesterdayPrice((int) daily[0])
                                        .gainPct(daily[1])
                                        .build();
                            }
                            return dto;
                        })
                        .toList();
        return Map.of(
                "content", enrichEngagementCounts(content),
                "totalElements", total,
                "totalPages", (int) Math.ceil((double) total / size),
                "page", page
        );
    }

    private Map<String, PriceSnapshot> snapshotsBySource(
            Map<String, Map<String, PriceSnapshot>> snapshots,
            String source) {
        return snapshots.entrySet().stream()
                .filter(entry -> entry.getValue().containsKey(source))
                .collect(Collectors.toMap(Map.Entry::getKey, entry -> entry.getValue().get(source)));
    }

    private record CountCacheEntry(long total, long createdAtNanos) {
    }

    @Override
    public ReturnData<List<CardDto>> getCardsByProduct(String productId) {
        if (productId == null || productId.isBlank()) {
            return ReturnData.badRequest("productId는 필수입니다.");
        }
        List<CardDto> cards = cardRepository.findByProductId(productId)
                .stream()
                .map(CardDto::from)
                .toList();
        return ReturnData.success(cards);
    }

    @Override
    public ReturnData<List<CardDto>> getCardsByCollectionNumber(String collectionNumber, String language) {
        List<Card> cards = cardRepository.findByCollectionNumberAndLanguage(collectionNumber, language);
        if (cards.isEmpty()) {
            return ReturnData.notFound("카드를 찾을 수 없습니다. number=" + collectionNumber);
        }
        return ReturnData.success(cards.stream().map(CardDto::from).toList());
    }

    @Override
    public ReturnData<CardDto> registerScanResult(ParameterData parameterData) {
        String officialCardCode = parameterData.getString("officialCardCode");
        if (officialCardCode == null || officialCardCode.isBlank()) {
            return ReturnData.badRequest("officialCardCode는 필수입니다.");
        }
        Optional<Card> card = cardRepository.findByOfficialCardCode(officialCardCode);
        return card.<ReturnData<CardDto>>map(c -> ReturnData.success(CardDto.from(c)))
                .orElseGet(() -> ReturnData.notFound("스캔된 카드를 DB에서 찾을 수 없습니다. code=" + officialCardCode));
    }
}
