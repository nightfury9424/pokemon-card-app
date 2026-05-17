package com.fury.back.domain.price;

import com.fury.back.common.IdGenerator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;

import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.Map;

/**
 * USD/JPY → KRW 환율 단일 진입점.
 * 우선순위: 메모리 캐시(1h) → DB 오늘자(price_snapshots SYSTEM) → open.er-api.com 외부 호출 + DB 저장.
 * Python 스크립트(price_scrydex.py / recalc_coefficients.py)도 DB 같은 출처를 조회하여 환율 단일화.
 * REFACTOR_2026-05-12.md 2-① 참조.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ExchangeRateClient {

    private static final double FALLBACK_USD_KRW = 1380.0;
    private static final double FALLBACK_JPY_KRW = 9.2;
    private static final long CACHE_TTL_MS = 60L * 60L * 1000L;

    static final String EX_CARD_USD = "exchange_rate_usd";
    static final String EX_CARD_JPY = "exchange_rate_jpy";
    static final String EX_SOURCE   = "SYSTEM";

    private final PriceSnapshotRepository priceSnapshotRepository;

    private final RestClient restClient = RestClient.builder()
            .baseUrl("https://open.er-api.com/v6")
            .build();

    private volatile CachedRates cache;

    private record CachedRates(double usd, double jpy, long fetchedAt) {}

    public double getUsdToKrw() {
        return getRates().usd;
    }

    public double getJpyToKrw() {
        return getRates().jpy;
    }

    private synchronized CachedRates getRates() {
        long now = System.currentTimeMillis();
        CachedRates current = cache;
        if (current != null && (now - current.fetchedAt) < CACHE_TTL_MS) return current;

        LocalDate today = LocalDate.now();
        Double dbUsd = loadFromDb(EX_CARD_USD, today);
        Double dbJpy = loadFromDb(EX_CARD_JPY, today);
        if (dbUsd != null && dbJpy != null) {
            CachedRates fromDb = new CachedRates(dbUsd, dbJpy, now);
            this.cache = fromDb;
            return fromDb;
        }

        FetchedRates fetched = fetchFromApi();
        double usd = (dbUsd != null) ? dbUsd : fetched.usd;
        double jpy = (dbJpy != null) ? dbJpy : fetched.jpy;

        // 외부 API 성공 시에만 DB 영속화 — fallback 값이 하루 종일 박히는 사고 방지
        // (REFACTOR_2026-05-12.md Hotfix-A, Codex CRITICAL #3)
        if (fetched.fromApi) {
            if (dbUsd == null) saveToDb(EX_CARD_USD, usd, today);
            if (dbJpy == null) saveToDb(EX_CARD_JPY, jpy, today);
        } else {
            log.warn("[ExchangeRate] 외부 API 실패 → fallback({}, {}). DB/캐시는 메모리에서만 사용, 영속화 안 함",
                    fetched.usd, fetched.jpy);
        }

        CachedRates fresh = new CachedRates(usd, jpy, now);
        this.cache = fresh;
        return fresh;
    }

    private record FetchedRates(double usd, double jpy, boolean fromApi) {}

    private Double loadFromDb(String cardId, LocalDate todayLocal) {
        return priceSnapshotRepository
                .findFirstByCardIdAndSourceOrderByTradedAtDesc(cardId, EX_SOURCE)
                .filter(ps -> !ps.getTradedAt().toLocalDate().isBefore(todayLocal))
                .map(ps -> ps.getPrice() / 100.0)
                .orElse(null);
    }

    private void saveToDb(String cardId, double value, LocalDate todayLocal) {
        boolean exists = priceSnapshotRepository
                .existsByCardIdAndSourceAndTradedAtAfter(cardId, EX_SOURCE, todayLocal.atStartOfDay());
        if (exists) return;
        LocalDateTime now = LocalDateTime.now();
        PriceSnapshot snap = PriceSnapshot.builder()
                .priceSnapshotId(IdGenerator.generate())
                .cardId(cardId)
                .source(EX_SOURCE)
                .price((int) Math.round(value * 100))
                .cardStatus("RAW")
                .tradedAt(now)
                .collectedAt(now)
                .build();
        try {
            priceSnapshotRepository.save(snap);
            log.info("[ExchangeRate] {} 저장: {} (×100={})", cardId, value, snap.getPrice());
        } catch (DataIntegrityViolationException dup) {
            // 3차-D (Codex CRITICAL #4): Java/Python 동시 INSERT 시 unique violation 무시.
            // 한쪽이 먼저 박았으니 다른 쪽은 그대로 진행. DB에 이미 오늘자 환율 있음.
            log.debug("[ExchangeRate] {} 동시 저장 race — 이미 다른 프로세스가 박음, 무시", cardId);
        }
    }

    /** open.er-api.com 호출. fromApi=true(성공) or false(실패→fallback). */
    @SuppressWarnings("unchecked")
    private FetchedRates fetchFromApi() {
        try {
            Map<String, Object> response = restClient.get()
                    .uri("/latest/USD")
                    .retrieve()
                    .body(Map.class);
            if (response == null) {
                return new FetchedRates(FALLBACK_USD_KRW, FALLBACK_JPY_KRW, false);
            }

            Map<String, Object> rates = (Map<String, Object>) response.get("rates");
            if (rates == null) {
                return new FetchedRates(FALLBACK_USD_KRW, FALLBACK_JPY_KRW, false);
            }

            if (!(rates.get("KRW") instanceof Number krwNum)) {
                return new FetchedRates(FALLBACK_USD_KRW, FALLBACK_JPY_KRW, false);
            }
            double usd = krwNum.doubleValue();
            double jpy = FALLBACK_JPY_KRW;
            Object jpyObj = rates.get("JPY");
            if (jpyObj instanceof Number jpyNum && jpyNum.doubleValue() > 0) {
                jpy = usd / jpyNum.doubleValue();
            }
            return new FetchedRates(usd, jpy, true);
        } catch (Exception e) {
            log.warn("환율 외부 조회 실패, fallback 사용: {}", e.getMessage());
            return new FetchedRates(FALLBACK_USD_KRW, FALLBACK_JPY_KRW, false);
        }
    }
}
