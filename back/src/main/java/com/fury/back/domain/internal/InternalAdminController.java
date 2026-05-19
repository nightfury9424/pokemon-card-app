package com.fury.back.domain.internal;

import java.util.Map;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.fury.back.domain.price.GlobalPriceService;

/**
 * /api/internal/admin/** — 내부 운영 endpoint.
 *
 * <p>외부 노출 X. nginx에서 /api/internal/ 차단 + InternalTokenFilter token 검증.
 * KO refresh, cron 수동 trigger, 장애 복구 등.
 */
@RestController
@RequestMapping("/api/internal/admin")
public class InternalAdminController {

    private final GlobalPriceService globalPriceService;

    public InternalAdminController(GlobalPriceService globalPriceService) {
        this.globalPriceService = globalPriceService;
    }

    /** PriceController#refreshKoEstimates와 동일 — 내부 토큰만으로 호출 가능. */
    @PostMapping("/refresh-ko-estimates")
    public Map<String, Object> refreshKoEstimates() {
        return globalPriceService.refreshKoEstimatesFromSnapshots();
    }
}
