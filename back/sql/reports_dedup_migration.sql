-- 2026-06-26 신고 중복 기준 분리: 게시판=글/댓글 단위(per-target), 비게시판=대상 사용자 단위(per-user).
-- ★uq_reports_reporter_target 은 partial UNIQUE INDEX (pg_constraint 아님, pg_indexes 확인) → DROP INDEX 사용.
--   작은 테이블이라 일반 트랜잭션으로 처리. CREATE INDEX CONCURRENTLY 금지(트랜잭션 내부 불가).
-- ★코드(ReportController per-type dedup + ReportService DEDUP_CONSTRAINTS)와 한 배포 단위로 같이 적용할 것.
BEGIN;

-- 1) 기존 per-user partial unique index → 비게시판 전용으로 교체(게시판 제외).
DROP INDEX uq_reports_reporter_target;
CREATE UNIQUE INDEX uq_reports_reporter_target
    ON reports (reporter_id, target_user_id)
    WHERE target_user_id IS NOT NULL
      AND target_type NOT IN ('BOARD_POST', 'BOARD_COMMENT');

-- 2) 게시판 전용 per-target partial unique index 신규.
CREATE UNIQUE INDEX uq_reports_reporter_board_target
    ON reports (reporter_id, target_type, target_id)
    WHERE target_type IN ('BOARD_POST', 'BOARD_COMMENT');

COMMIT;
