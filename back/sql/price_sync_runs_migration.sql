-- price_sync_runs: Missed cron catch-up + retry + dedup 단일 진실원
-- 2026-05-19 Phase 1: SCRYDEX_DAILY + REFRESH_KO_ESTIMATED 지원
-- docs/MISSED_CRON_CATCHUP.md 참조

CREATE TABLE IF NOT EXISTS price_sync_runs (
  id              BIGSERIAL    PRIMARY KEY,
  job_name        VARCHAR(50)  NOT NULL,
  business_date   DATE         NOT NULL,
  status          VARCHAR(20)  NOT NULL,    -- RUNNING / SUCCESS / FAILED / SKIPPED
  trigger_source  VARCHAR(20)  NOT NULL,    -- CRON / STARTUP / WATCHDOG / MANUAL
  scheduled_at    TIMESTAMPTZ  NOT NULL,    -- bizDate scheduled time (Asia/Seoul)
  started_at      TIMESTAMPTZ  NOT NULL,
  ended_at        TIMESTAMPTZ,
  row_count_en    INTEGER,
  row_count_jp    INTEGER,
  retry_count     INTEGER      NOT NULL DEFAULT 0,
  error_message   TEXT,
  notified_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  CONSTRAINT uq_price_sync_runs UNIQUE (job_name, business_date)
);

CREATE INDEX IF NOT EXISTS idx_psr_lookup
  ON price_sync_runs (business_date, job_name, status);

CREATE INDEX IF NOT EXISTS idx_psr_stale
  ON price_sync_runs (status, started_at)
  WHERE status = 'RUNNING';

COMMENT ON TABLE price_sync_runs IS
  'Missed cron catch-up 추적용. SUCCESS=primary source. UNIQUE(job_name, business_date).';
