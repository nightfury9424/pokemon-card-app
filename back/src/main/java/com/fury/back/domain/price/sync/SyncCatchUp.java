package com.fury.back.domain.price.sync;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.context.event.ApplicationReadyEvent;
import org.springframework.context.event.EventListener;
import org.springframework.scheduling.annotation.Async;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Catch-up 진입점: ApplicationReadyEvent (서버 시작) + watchdog (10분 주기).
 *
 * CRON 진입점은 기존 PriceSyncScheduler에 있으며 본 클래스에 추가하지 않는다
 * (사용자 보정: 신규 21:00 cron 추가 금지).
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class SyncCatchUp {

    private final ScrydexSyncService scrydexSync;
    private final KoEstimatedSyncService koSync;
    private final PriceSyncRunRepository runRepo;

    /**
     * 서버 시작 시 catch-up. @Async로 readiness 차단 방지.
     * (price_scrydex.py가 30분 걸리더라도 startup이 그동안 block되면 안 됨)
     */
    @Async("syncCatchUpExecutor")
    @EventListener(ApplicationReadyEvent.class)
    public void onReady() {
        log.info("[SyncCatchUp] STARTUP catch-up 시작");
        try {
            scrydexSync.runIfNeeded(TriggerSource.STARTUP);
            // SCRYDEX SUCCESS 시 내부에서 KO trigger됨. 명시 호출도 idempotent.
            koSync.runIfNeeded(TriggerSource.STARTUP);
        } catch (Exception e) {
            log.error("[SyncCatchUp] STARTUP 실패", e);
        }
    }

    /** Watchdog — 10분 주기. stale reap → SCRYDEX → KO. */
    @Scheduled(fixedDelay = 600_000L)
    public void watchdog() {
        try {
            int reaped = runRepo.reapStaleRunning(SyncJobSchedule.STALE_TIMEOUT_MINUTES);
            if (reaped > 0) {
                log.warn("[SyncCatchUp] stale RUNNING reaped: {}", reaped);
            }
            scrydexSync.runIfNeeded(TriggerSource.WATCHDOG);
            koSync.runIfNeeded(TriggerSource.WATCHDOG);
        } catch (Exception e) {
            log.error("[SyncCatchUp] watchdog 실패", e);
        }
    }
}
