package com.fury.back.domain.price.sync;

import jakarta.persistence.EntityManager;
import jakarta.persistence.NoResultException;
import jakarta.persistence.PersistenceContext;
import lombok.RequiredArgsConstructor;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.Optional;

/**
 * PriceSyncRunRepository custom impl. 모든 mutating method는 REQUIRES_NEW.
 *
 * 트랜잭션 격리 이유: ScrydexSyncService.runIfNeeded()는 트랜잭션 없이 호출되어
 * Python 30분 ProcessBuilder 실행 동안 DB 커넥션을 잡지 않는다. claim / mark 시점에만
 * 짧은 REQUIRES_NEW 트랜잭션을 따로 열고 즉시 commit한다.
 */
@RequiredArgsConstructor
public class PriceSyncRunRepositoryImpl implements PriceSyncRunRepositoryCustom {

    @PersistenceContext
    private EntityManager em;

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<Long> tryClaimRunning(String jobName, LocalDate businessDate,
                                          OffsetDateTime scheduledAt, TriggerSource source) {
        try {
            Object result = em.createNativeQuery("""
                INSERT INTO price_sync_runs
                  (job_name, business_date, status, trigger_source,
                   scheduled_at, started_at, retry_count, created_at)
                VALUES
                  (:jobName, :bizDate, 'RUNNING', :source,
                   :scheduledAt, NOW(), 0, NOW())
                ON CONFLICT (job_name, business_date) DO NOTHING
                RETURNING id
                """)
                .setParameter("jobName", jobName)
                .setParameter("bizDate", businessDate)
                .setParameter("source", source.name())
                .setParameter("scheduledAt", scheduledAt)
                .getSingleResult();
            return result == null ? Optional.empty() : Optional.of(((Number) result).longValue());
        } catch (NoResultException e) {
            return Optional.empty();
        }
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Optional<Long> tryClaimRetry(Long runId, int maxRetry) {
        int updated = em.createNativeQuery("""
            UPDATE price_sync_runs
               SET status = 'RUNNING',
                   retry_count = retry_count + 1,
                   started_at = NOW(),
                   ended_at = NULL,
                   error_message = NULL
             WHERE id = :runId
               AND status = 'FAILED'
               AND retry_count < :maxRetry
            """)
            .setParameter("runId", runId)
            .setParameter("maxRetry", maxRetry)
            .executeUpdate();
        return updated > 0 ? Optional.of(runId) : Optional.empty();
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public int reapStaleRunning(int timeoutMinutes) {
        return em.createNativeQuery("""
            UPDATE price_sync_runs
               SET status = 'FAILED',
                   ended_at = NOW(),
                   error_message = COALESCE(error_message, '') || ' [stale-reaped]'
             WHERE status = 'RUNNING'
               AND started_at < NOW() - make_interval(mins => :timeout)
            """)
            .setParameter("timeout", timeoutMinutes)
            .executeUpdate();
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public boolean markNotifiedIfNotYet(Long runId) {
        int updated = em.createNativeQuery("""
            UPDATE price_sync_runs
               SET notified_at = NOW()
             WHERE id = :runId
               AND notified_at IS NULL
            """)
            .setParameter("runId", runId)
            .executeUpdate();
        return updated > 0;
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markSuccess(Long runId, Integer rowCountEn, Integer rowCountJp, String warnNote) {
        em.createNativeQuery("""
            UPDATE price_sync_runs
               SET status = 'SUCCESS',
                   ended_at = NOW(),
                   row_count_en = :en,
                   row_count_jp = :jp,
                   error_message = :note
             WHERE id = :runId
            """)
            .setParameter("runId", runId)
            .setParameter("en", rowCountEn)
            .setParameter("jp", rowCountJp)
            .setParameter("note", warnNote)
            .executeUpdate();
    }

    @Override
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public void markFailed(Long runId, String error) {
        em.createNativeQuery("""
            UPDATE price_sync_runs
               SET status = 'FAILED',
                   ended_at = NOW(),
                   error_message = :error
             WHERE id = :runId
            """)
            .setParameter("runId", runId)
            .setParameter("error", truncate(error, 4000))
            .executeUpdate();
    }

    private String truncate(String s, int max) {
        if (s == null) return null;
        return s.length() <= max ? s : s.substring(0, max);
    }
}
