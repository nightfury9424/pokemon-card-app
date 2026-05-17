package com.fury.back.domain.price;

import com.fury.back.domain.price.dto.MarketCoefficientDto;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Component;

import java.util.concurrent.atomic.AtomicReference;

/**
 * 한국 시장 계수를 메모리에 캐싱.
 * - 서버 시작 시 null (첫 요청 또는 스케줄러가 채워줌)
 * - 매일 새벽 스케줄러가 scrydex 수집 후 recalculate() 호출 → 갱신
 * - getOrNull()이 null이면 GlobalPriceService가 즉석 계산
 */
@Slf4j
@Component
public class CoefficientCache {

    private final AtomicReference<MarketCoefficientDto> cache = new AtomicReference<>(null);

    public void update(MarketCoefficientDto dto) {
        cache.set(dto);
        log.info("[CoefficientCache] 업데이트: coefficient={}, sampleSize={}, exchangeRate={}",
                dto.getCoefficient(), dto.getSampleSize(), dto.getExchangeRate());
    }

    public MarketCoefficientDto getOrNull() {
        return cache.get();
    }
}
