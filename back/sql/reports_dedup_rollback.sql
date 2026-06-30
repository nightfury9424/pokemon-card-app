-- 롤백: 작업 전 상태 복원.
--   원본 uq_reports_reporter_target = CREATE UNIQUE INDEX ... (reporter_id, target_user_id) WHERE (target_user_id IS NOT NULL)
BEGIN;
DROP INDEX IF EXISTS uq_reports_reporter_board_target;
DROP INDEX uq_reports_reporter_target;
CREATE UNIQUE INDEX uq_reports_reporter_target
    ON reports (reporter_id, target_user_id)
    WHERE target_user_id IS NOT NULL;
COMMIT;
