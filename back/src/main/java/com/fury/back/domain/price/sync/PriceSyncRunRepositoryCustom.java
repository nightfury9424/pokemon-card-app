package com.fury.back.domain.price.sync;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Optional;

/**
 * price_sync_runs의 mutating 연산은 REQUIRES_NEW 트랜잭션으로 격리한다.
 * (ScrydexSyncService / KoEstimatedSyncService는 트랜잭션 없이 호출 — Python 외부 호출 30분 차단 방지)
 */
public interface PriceSyncRunRepositoryCustom {

    /**
     * INSERT ON CONFLICT DO NOTHING — 신규 RUNNING 등록 시도.
     * @return 신규 INSERT 되었으면 생성된 id, 이미 record 있으면 empty
     */
    Optional<Long> tryClaimRunning(String jobName, LocalDate businessDate,
                                   OffsetDateTime scheduledAt, TriggerSource source);

    /**
     * FAILED + retry_count < maxRetry → RUNNING 전환, retry_count++.
     * @return 전환 성공 시 runId, 아니면 empty (이미 max 도달 또는 status mismatch)
     */
    Optional<Long> tryClaimRetry(Long runId, int maxRetry);

    /** RUNNING + started_at < now() - timeoutMinutes → FAILED 전환. 반환: 회수된 row 수 */
    int reapStaleRunning(int timeoutMinutes);

    /** notified_at IS NULL일 때만 NOW로 set. 알림 중복 방지. */
    boolean markNotifiedIfNotYet(Long runId);

    /** SUCCESS 처리. warnNote가 있으면 error_message에 적재 (row=0 같은 SUCCESS_WITH_WARNING 케이스). */
    void markSuccess(Long runId, Integer rowCountEn, Integer rowCountJp, String warnNote);

    /** FAILED 처리. */
    void markFailed(Long runId, String error);
}
