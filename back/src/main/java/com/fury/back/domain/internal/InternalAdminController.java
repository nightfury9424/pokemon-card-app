package com.fury.back.domain.internal;

import java.util.Map;

import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
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

    /**
     * PriceController#backfillKoHistory와 동일 — 내부 토큰만으로 호출 가능.
     *
     * <p>운영 산식 그대로 N일 KO_ESTIMATED history backfill.
     * force=false 시 이미 KO 있는 카드 자동 skip → 신규 master INSERT 한 카드만 자동 타겟.
     *
     * <p>닌자스피너 27장 신규 INSERT (2026-05-30) 같은 case 에서 admin JWT 발급 없이 호출.
     */
    @PostMapping("/backfill-ko-history")
    public Map<String, Object> backfillKoHistory(
            @RequestParam(defaultValue = "14") int days,
            @RequestParam(defaultValue = "false") boolean force) {
        return globalPriceService.backfillKoEstimatedHistory(days, force);
    }
}
