-- price_sync_runs_bootstrap.sql
-- price_sync_runs 첫 도입 시 기존 SCRYDEX_EN/JP 적재 row 기준으로 SCRYDEX_DAILY SUCCESS 시드.
-- 이 시드가 없으면 23:45 KO_ESTIMATED catch-up이 "SCRYDEX_DAILY SUCCESS 없음"으로 skip된다.
--
-- 실행 순서:
--   1. price_sync_runs_migration.sql 적용
--   2. 본 SQL 실행
--   3. (선택) price.sync.catchup.enabled=true 로 backend 가동
--
-- 멱등 — UNIQUE(job_name, business_date)로 중복 방지.

INSERT INTO price_sync_runs (
  job_name, business_date, status, trigger_source,
  scheduled_at, started_at, ended_at,
  row_count_en, row_count_jp, retry_count, error_message, created_at
)
SELECT
  'SCRYDEX_DAILY' AS job_name,
  bd.business_date,
  'SUCCESS' AS status,
  'MANUAL' AS trigger_source,
  ((bd.business_date + TIME '21:00') AT TIME ZONE 'Asia/Seoul') AS scheduled_at,
  bd.min_created AS started_at,
  bd.max_created AS ended_at,
  bd.cnt_en, bd.cnt_jp, 0,
  '[bootstrap] seeded from existing SCRYDEX rows' AS error_message,
  NOW() AS created_at
FROM (
  SELECT
    (created_at AT TIME ZONE 'Asia/Seoul')::date AS business_date,
    MIN(created_at) AS min_created,
    MAX(created_at) AS max_created,
    COUNT(*) FILTER (WHERE source = 'SCRYDEX_EN') AS cnt_en,
    COUNT(*) FILTER (WHERE source = 'SCRYDEX_JP') AS cnt_jp
  FROM price_snapshots
  WHERE source IN ('SCRYDEX_EN', 'SCRYDEX_JP')
    AND created_at >= NOW() - INTERVAL '7 days'
  GROUP BY (created_at AT TIME ZONE 'Asia/Seoul')::date
) bd
WHERE bd.cnt_en + bd.cnt_jp > 0
ON CONFLICT (job_name, business_date) DO NOTHING;

-- 검증 쿼리
-- SELECT business_date, status, row_count_en, row_count_jp, trigger_source
--   FROM price_sync_runs
--  WHERE job_name = 'SCRYDEX_DAILY'
--  ORDER BY business_date DESC;
