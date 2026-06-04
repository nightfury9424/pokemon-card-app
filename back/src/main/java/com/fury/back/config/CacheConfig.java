package com.fury.back.config;

import com.github.benmanes.caffeine.cache.Caffeine;
import org.springframework.cache.CacheManager;
import org.springframework.cache.annotation.EnableCaching;
import org.springframework.cache.caffeine.CaffeineCacheManager;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.time.Duration;

/**
 * Caffeine in-memory 캐시 (단일 인스턴스 — Redis 불필요).
 *
 * <p>★ 전역 read-only + 일중 정적인 무거운 연산만 캐시한다. 가격은 KO_ESTIMATED 일일 cron(23:50)
 * 으로만 바뀌므로 30분 TTL 이면 일중 안전(다음날 갱신은 TTL 만료 후 자연 반영).
 *
 * <p>캐시 금지: 유저/거래/정지 등 가변·보안 데이터. (예: getMarketCards 는 매도/매수 count 섞여
 * 캐시 시 신규 매물이 TTL 동안 안 보임 → 제외. DeletedUserGuardFilter 정지 체크도 신선해야 함 → 제외.)
 *
 * <p>현재 캐시: {@code cardPriceSummary} — 카드 상세 가격/차트(GlobalPriceService.getCardPriceSummary,
 * 90일 히스토리 + 계수 + PSA 등 무거운 DB/연산, 거래 데이터 없음). null 결과는 캐시 안 함(서비스에서 unless 처리).
 */
@Configuration
@EnableCaching
public class CacheConfig {

    @Bean
    public CacheManager cacheManager() {
        CaffeineCacheManager manager = new CaffeineCacheManager("cardPriceSummary");
        manager.setCaffeine(Caffeine.newBuilder()
                .expireAfterWrite(Duration.ofMinutes(30))
                .maximumSize(4000));
        // 명시한 캐시 이름만 허용(오타/의도치 않은 캐시 생성 방지).
        manager.setAllowNullValues(false);
        return manager;
    }
}
