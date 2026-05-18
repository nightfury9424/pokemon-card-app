package com.fury.back.domain.price.sync;

import com.fury.back.domain.notification.NotificationService;
import com.fury.back.domain.price.GlobalPriceService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Map;
import java.util.Optional;

/**
 * REFRESH_KO_ESTIMATED catch-up service.
 *
 * - SCRYDEX_DAILY SUCCESS가 선행되어야 실행 (의존성 보호).
 * - globalPriceService.refreshKoEstimatesFromSnapshots()에 위임.
 * - rowCount=0 SUCCESS_WITH_WARNING 마커 적재.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class KoEstimatedSyncService {

    private final PriceSyncRunRepository runRepo;
    private final SyncJobSchedule schedule;
    private final NotificationService notificationService;
    private final GlobalPriceService globalPriceService;

    /** Kill switch — local 기본값 false. 운영에서 명시적 true로 enable. */
    @Value("${price.sync.catchup.enabled:false}")
    private boolean catchupEnabled;

    public SyncRunStatus runIfNeeded(TriggerSource source) {
        if (!catchupEnabled) {
            log.info("[KoEstimatedSync] catch-up DISABLED — skip (source={}, property=price.sync.catchup.enabled)", source);
            return SyncRunStatus.SKIPPED;
        }
        LocalDate bizDate = schedule.dueBusinessDate(SyncJobSchedule.JOB_REFRESH_KO);
        OffsetDateTime scheduledAt = schedule.scheduledAt(SyncJobSchedule.JOB_REFRESH_KO, bizDate);

        // 의존성: SCRYDEX_DAILY SUCCESS 선행 필수
        PriceSyncRun scrydex = runRepo.findByJobNameAndBusinessDate(
            SyncJobSchedule.JOB_SCRYDEX, bizDate).orElse(null);
        if (scrydex == null || scrydex.getStatus() != SyncRunStatus.SUCCESS) {
            log.info("[KoEstimatedSync] SCRYDEX_DAILY not SUCCESS yet — SKIP bizDate={}", bizDate);
            return SyncRunStatus.SKIPPED;
        }

        Optional<Long> newRunId = runRepo.tryClaimRunning(
            SyncJobSchedule.JOB_REFRESH_KO, bizDate, scheduledAt, source);

        Long runId;
        if (newRunId.isPresent()) {
            runId = newRunId.get();
            log.info("[KoEstimatedSync] CLAIMED new run id={} bizDate={}", runId, bizDate);
        } else {
            Optional<Long> resumedId = handleExistingRun(bizDate);
            if (resumedId.isEmpty()) return SyncRunStatus.SKIPPED;
            runId = resumedId.get();
        }

        try {
            Map<String, Object> result = globalPriceService.refreshKoEstimatesFromSnapshots();
            int savedCount = ((Number) result.getOrDefault("savedCount", 0)).intValue();

            if (savedCount == 0) {
                log.warn("[KoEstimatedSync] rowCount=0 — SUCCESS_WITH_WARNING (운영 추적 마커 적재)");
                runRepo.markSuccess(runId, null, null, "[warn] rowCount=0");
            } else {
                runRepo.markSuccess(runId, savedCount, null, null);
            }
            log.info("[KoEstimatedSync] SUCCESS bizDate={} saved={}", bizDate, savedCount);
            return SyncRunStatus.SUCCESS;
        } catch (Exception e) {
            log.error("[KoEstimatedSync] 실행 실패", e);
            runRepo.markFailed(runId, e.getMessage());
            return SyncRunStatus.FAILED;
        }
    }

    private Optional<Long> handleExistingRun(LocalDate bizDate) {
        PriceSyncRun existing = runRepo.findByJobNameAndBusinessDate(
            SyncJobSchedule.JOB_REFRESH_KO, bizDate).orElse(null);
        if (existing == null) {
            log.warn("[KoEstimatedSync] race — claim conflict but no row");
            return Optional.empty();
        }
        return switch (existing.getStatus()) {
            case SUCCESS -> Optional.empty();
            case RUNNING -> {
                if (existing.getStartedAt().isAfter(
                        OffsetDateTime.now().minusMinutes(SyncJobSchedule.STALE_TIMEOUT_MINUTES))) {
                    log.info("[KoEstimatedSync] another RUNNING in progress — SKIP");
                } else {
                    log.warn("[KoEstimatedSync] stale RUNNING id={} — watchdog reap 대기",
                        existing.getId());
                }
                yield Optional.empty();
            }
            case FAILED -> {
                Optional<Long> retry = runRepo.tryClaimRetry(existing.getId(), SyncJobSchedule.MAX_RETRY);
                if (retry.isEmpty()) {
                    if (runRepo.markNotifiedIfNotYet(existing.getId())) {
                        notificationService.notifyOpsFailure(
                            SyncJobSchedule.JOB_REFRESH_KO,
                            existing.getRetryCount(),
                            "retry exhausted: " + existing.getErrorMessage());
                    }
                    yield Optional.empty();
                }
                log.info("[KoEstimatedSync] RETRY claimed id={}", retry.get());
                yield retry;
            }
            case SKIPPED -> Optional.empty();
        };
    }
}
