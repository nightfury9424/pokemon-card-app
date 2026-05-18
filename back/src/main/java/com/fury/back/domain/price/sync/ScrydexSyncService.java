package com.fury.back.domain.price.sync;

import com.fury.back.domain.notification.NotificationService;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

/**
 * SCRYDEX_DAILY catch-up service.
 *
 * - runIfNeeded는 트랜잭션 없음. Repository 메서드(REQUIRES_NEW)로 짧은 commit만.
 * - executeScrydex는 ProcessBuilder로 price_scrydex.py 호출 (30분), 트랜잭션 밖.
 * - SUCCESS 후 KoEstimatedSyncService 연쇄 trigger.
 */
@Slf4j
@Service
@RequiredArgsConstructor
public class ScrydexSyncService {

    private static final String PYTHON3 = "/usr/bin/python3";
    private static final String SCRAPER_PATH =
        "/Users/fury/pokemon-card-app/python/price_scrydex.py";

    private final PriceSyncRunRepository runRepo;
    private final SyncJobSchedule schedule;
    private final NotificationService notificationService;
    private final KoEstimatedSyncService koEstimatedSyncService;

    @PersistenceContext
    private EntityManager em;

    /** Kill switch — local 기본값 false. 운영에서 명시적 true로 enable. */
    @Value("${price.sync.catchup.enabled:false}")
    private boolean catchupEnabled;

    public SyncRunStatus runIfNeeded(TriggerSource source) {
        if (!catchupEnabled) {
            log.info("[ScrydexSync] catch-up DISABLED — skip (source={}, property=price.sync.catchup.enabled)", source);
            return SyncRunStatus.SKIPPED;
        }
        LocalDate bizDate = schedule.dueBusinessDate(SyncJobSchedule.JOB_SCRYDEX);
        OffsetDateTime scheduledAt = schedule.scheduledAt(SyncJobSchedule.JOB_SCRYDEX, bizDate);

        Optional<Long> newRunId = runRepo.tryClaimRunning(
            SyncJobSchedule.JOB_SCRYDEX, bizDate, scheduledAt, source);

        Long runId;
        if (newRunId.isPresent()) {
            runId = newRunId.get();
            log.info("[ScrydexSync] CLAIMED new run id={} bizDate={} source={}",
                runId, bizDate, source);
        } else {
            Optional<Long> resumedId = handleExistingRun(bizDate);
            if (resumedId.isEmpty()) return SyncRunStatus.SKIPPED;
            runId = resumedId.get();
        }

        // Python 실행 — 트랜잭션 밖
        ExecuteResult result = executeScrydex();

        if (result.success) {
            int total = result.rowCountEn + result.rowCountJp;
            if (total == 0) {
                log.warn("[ScrydexSync] rowCount=0 → FAILED (Scrydex 0건은 호출 실패 간주)");
                runRepo.markFailed(runId, "rowCount=0 — Scrydex 응답 0건");
                return SyncRunStatus.FAILED;
            }
            runRepo.markSuccess(runId, result.rowCountEn, result.rowCountJp, null);
            log.info("[ScrydexSync] SUCCESS bizDate={} EN={} JP={}",
                bizDate, result.rowCountEn, result.rowCountJp);

            // SUCCESS → KO_ESTIMATED 연쇄 trigger
            try {
                koEstimatedSyncService.runIfNeeded(TriggerSource.WATCHDOG);
            } catch (Exception e) {
                log.warn("[ScrydexSync] downstream KO trigger 실패: {}", e.getMessage());
            }
            return SyncRunStatus.SUCCESS;
        } else {
            runRepo.markFailed(runId, result.errorMessage);
            return SyncRunStatus.FAILED;
        }
    }

    /** 기존 row 있을 때 — SUCCESS/RUNNING/FAILED 분기. retry 가능하면 runId 반환, 아니면 empty. */
    private Optional<Long> handleExistingRun(LocalDate bizDate) {
        PriceSyncRun existing = runRepo.findByJobNameAndBusinessDate(
            SyncJobSchedule.JOB_SCRYDEX, bizDate).orElse(null);
        if (existing == null) {
            log.warn("[ScrydexSync] race — claim conflict but no row");
            return Optional.empty();
        }
        return switch (existing.getStatus()) {
            case SUCCESS -> {
                log.debug("[ScrydexSync] already SUCCESS bizDate={}", bizDate);
                yield Optional.empty();
            }
            case RUNNING -> {
                if (existing.getStartedAt().isAfter(
                        OffsetDateTime.now().minusMinutes(SyncJobSchedule.STALE_TIMEOUT_MINUTES))) {
                    log.info("[ScrydexSync] another RUNNING in progress — SKIP");
                } else {
                    log.warn("[ScrydexSync] stale RUNNING id={} — watchdog reap에 위임",
                        existing.getId());
                }
                yield Optional.empty();
            }
            case FAILED -> {
                Optional<Long> retry = runRepo.tryClaimRetry(existing.getId(), SyncJobSchedule.MAX_RETRY);
                if (retry.isEmpty()) {
                    if (runRepo.markNotifiedIfNotYet(existing.getId())) {
                        notificationService.notifyOpsFailure(
                            SyncJobSchedule.JOB_SCRYDEX,
                            existing.getRetryCount(),
                            "retry exhausted: " + existing.getErrorMessage());
                    }
                    yield Optional.empty();
                }
                log.info("[ScrydexSync] RETRY claimed id={}", retry.get());
                yield retry;
            }
            case SKIPPED -> Optional.empty();
        };
    }

    /** Python 호출 — 트랜잭션 밖. */
    private ExecuteResult executeScrydex() {
        StringBuilder tail = new StringBuilder();
        try {
            List<String> cmd = new ArrayList<>();
            cmd.add(PYTHON3);
            cmd.add(SCRAPER_PATH);
            ProcessBuilder pb = new ProcessBuilder(cmd);
            pb.redirectErrorStream(true);
            Process process = pb.start();

            try (BufferedReader reader = new BufferedReader(
                    new InputStreamReader(process.getInputStream()))) {
                String line;
                while ((line = reader.readLine()) != null) {
                    log.info("[scrydex-py] {}", line);
                    tail.append(line).append('\n');
                    if (tail.length() > 4000) tail.delete(0, tail.length() - 2000);
                }
            }
            int exitCode = process.waitFor();
            if (exitCode != 0) {
                return ExecuteResult.failure("exit=" + exitCode + " tail=" + tail);
            }

            int en = countTodayScrydex("SCRYDEX_EN");
            int jp = countTodayScrydex("SCRYDEX_JP");
            return ExecuteResult.success(en, jp);
        } catch (Exception e) {
            log.error("[ScrydexSync] 실행 실패", e);
            return ExecuteResult.failure(e.getMessage());
        }
    }

    /** 오늘(KST) 적재된 SCRYDEX row 수. price_scrydex.py가 stdout으로 카운트 안 주므로 직접 조회. */
    private int countTodayScrydex(String source) {
        LocalDate today = LocalDate.now(SyncJobSchedule.KST);
        OffsetDateTime startOfDay = today.atStartOfDay(SyncJobSchedule.KST).toOffsetDateTime();
        Object result = em.createNativeQuery("""
            SELECT COUNT(*) FROM price_snapshots
            WHERE source = :source
              AND created_at >= :startOfDay
            """)
            .setParameter("source", source)
            .setParameter("startOfDay", startOfDay)
            .getSingleResult();
        return ((Number) result).intValue();
    }

    private record ExecuteResult(boolean success, int rowCountEn, int rowCountJp, String errorMessage) {
        static ExecuteResult success(int en, int jp) {
            return new ExecuteResult(true, en, jp, null);
        }
        static ExecuteResult failure(String error) {
            return new ExecuteResult(false, 0, 0, error);
        }
    }
}
