-- =============================================================
-- Onboarding + 닉네임 정책 마이그레이션 (2026-05-12)
-- - nickname을 nullable로 변경 (온보딩 전 사용자용)
-- - onboarded, nickname_changed_at 컬럼 추가
-- - LOWER(nickname) partial unique index 추가
-- =============================================================

BEGIN;

-- 1) nickname을 nullable로
ALTER TABLE users ALTER COLUMN nickname DROP NOT NULL;

-- 2) onboarded 추가 (기존 사용자는 이미 닉네임이 있으므로 true)
ALTER TABLE users ADD COLUMN IF NOT EXISTS onboarded BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE users SET onboarded = TRUE WHERE nickname IS NOT NULL AND onboarded = FALSE;

-- 2.5) 중복 닉네임 정리 — 같은 lowercase nickname을 가진 사용자 중 가장 오래된 것 NULL/onboarded=false로 reset.
-- 닉네임 unique index를 만들기 전에 정리해야 함. 최근 가입자가 닉네임을 유지하고, 이전 가입자는 onboarding을 다시 거침.
UPDATE users
SET nickname = NULL, onboarded = FALSE
WHERE user_id IN (
    SELECT user_id FROM (
        SELECT user_id,
               ROW_NUMBER() OVER (PARTITION BY LOWER(nickname) ORDER BY created_at DESC) AS rn
        FROM users
        WHERE nickname IS NOT NULL
    ) ranked
    WHERE rn > 1
);

-- 3) nickname_changed_at 추가
ALTER TABLE users ADD COLUMN IF NOT EXISTS nickname_changed_at TIMESTAMP;

-- 4) LOWER(nickname) partial unique index
CREATE UNIQUE INDEX IF NOT EXISTS users_nickname_lower_idx
    ON users (LOWER(nickname))
    WHERE nickname IS NOT NULL;

COMMIT;
