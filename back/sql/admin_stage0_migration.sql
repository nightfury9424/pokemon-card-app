-- 관리자 페이지 Stage 0 마이그레이션 (2026-05-29)
-- Codex 사전 리뷰 (agent ac14f3462c3796677) 권장 그대로.
--
-- 목적:
--   1. 신고 처리 워크플로우 (status 변경 + admin 메모 + 처리 시각/주체 기록)
--   2. 사용자 정지 (정지/복구, deleted_at 재사용 X)
--   3. admin actions audit log (App Review 5.1.5 의무)
--
-- low-lock 패턴 (어제 b83d0770 Codex 사후 리뷰 패턴):
--   - ADD COLUMN 은 짧은 ACCESS EXCLUSIVE (sub-second)
--   - CREATE INDEX 는 CONCURRENTLY (write 차단 X)
--   - 적용 순서: psql 에서 step 별 실행. 한 번에 실행 X (CONCURRENTLY 는 트랜잭션 안 X).

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 1. reports 테이블 — admin 처리 메타 컬럼 추가.
-- ─────────────────────────────────────────────────────────────────────────

ALTER TABLE reports
    ADD COLUMN IF NOT EXISTS admin_memo TEXT;

ALTER TABLE reports
    ADD COLUMN IF NOT EXISTS handled_by VARCHAR(50);

ALTER TABLE reports
    ADD COLUMN IF NOT EXISTS handled_at TIMESTAMP;

-- SUSPEND_USER / DELETE_TRADE / DELETE_CHAT / DISMISS / NONE.
ALTER TABLE reports
    ADD COLUMN IF NOT EXISTS resolution_action VARCHAR(40);

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 2. users 테이블 — 정지/복구 컬럼 (Codex C — deleted_at 재사용 X).
--   suspended_at NOT NULL = 정지 중 / NULL = 정상.
-- ─────────────────────────────────────────────────────────────────────────

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS suspended_at TIMESTAMP;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS suspension_reason TEXT;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS suspended_by VARCHAR(50);

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS unsuspended_at TIMESTAMP;

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 3. admin_actions 테이블 — 모든 admin 액션 immutable audit (Codex I).
--   App Review 5.1.5 moderation evidence 의무.
-- ─────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS admin_actions (
    action_id        VARCHAR(50) PRIMARY KEY,
    admin_user_id    VARCHAR(50) NOT NULL,
    action_type      VARCHAR(40) NOT NULL,    -- SUSPEND / UNSUSPEND / DELETE_TRADE / DELETE_CHAT_MESSAGE / DISMISS_REPORT / REVIEW_REPORT 등
    target_type      VARCHAR(20) NOT NULL,    -- USER / TRADE / REPORT / CHAT_MESSAGE
    target_id        VARCHAR(50) NOT NULL,
    report_id        VARCHAR(50),             -- 신고 기반 처리 시 link (nullable — 직접 액션은 NULL)
    memo             TEXT,
    previous_state   VARCHAR(40),             -- 변경 전 상태 스냅 (e.g. "OPEN", "ACTIVE")
    new_state        VARCHAR(40),             -- 변경 후 상태 스냅
    metadata_json    TEXT,                    -- 추가 컨텍스트 (JSON 직렬화)
    created_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 4. 인덱스 CONCURRENTLY (write 차단 X) — 어제 패턴 일관.
-- ─────────────────────────────────────────────────────────────────────────

-- 신고 list — status 별 시간순 정렬 (default PENDING newest first).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_reports_status_created
    ON reports (status, created_at DESC);

-- admin actions 조회 — admin 별 시간순 (audit trail) + target 별 조회.
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_admin_actions_admin_created
    ON admin_actions (admin_user_id, created_at DESC);

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_admin_actions_target
    ON admin_actions (target_type, target_id);

-- 사용자 정지 query — suspended_at NOT NULL row 만 (정지 사용자 list).
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_suspended
    ON users (suspended_at)
    WHERE suspended_at IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- 검증 쿼리 (모든 step 후):
--   \d reports
--   \d users
--   \d admin_actions
--   SELECT indexname FROM pg_indexes WHERE tablename IN ('reports', 'users', 'admin_actions')
--     AND indexname LIKE '%suspended%' OR indexname LIKE '%admin_actions%' OR indexname LIKE '%reports_status%';
-- ─────────────────────────────────────────────────────────────────────────
