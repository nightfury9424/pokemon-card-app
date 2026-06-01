-- ============================================================================
-- V20260528__add_user_deleted_at.sql
-- ============================================================================
-- 계정 탈퇴(soft delete) 지원 — App Review 5.1.1 대응.
--
-- users.deleted_at = NULL → 활성. != NULL → 탈퇴 처리됨 (DeletedUserGuardFilter
-- 에서 인증 API 호출 시 401 + USER_DELETED).
--
-- 단순 soft-delete column 추가. PII 마스킹은 application 레벨(UserService)에서
-- 처리 — DB에 plain text PII 남기지 않기 위해 nickname/email/profile_image_url을
-- 별도 UPDATE로 null/마스킹. 자세한 정책은 docs/DELETION_POLICY.md 참조.
--
-- 적용 방법:
--   ssh -i /Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120
--   docker exec -i pokefolio-postgres psql -U fury -d pokemon_card_db < V20260528__add_user_deleted_at.sql
-- 또는 인터랙티브:
--   docker exec -it pokefolio-postgres psql -U fury -d pokemon_card_db
--   (이 파일 내용 paste)
-- ============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMP NULL;

-- 탈퇴 계정 차단 필터가 빈번하게 deleted_at IS NULL 체크 → partial index 추가.
-- (전체 인덱스 대신 NULL만 인덱싱 — 활성 계정이 다수라 효율).
CREATE INDEX IF NOT EXISTS idx_users_deleted_at_not_null
    ON users(deleted_at)
    WHERE deleted_at IS NOT NULL;

-- 무결성 확인 — 기존 row는 모두 NULL이어야 함 (활성 사용자).
-- SELECT count(*) FROM users WHERE deleted_at IS NOT NULL;  -- 0이어야 정상.
