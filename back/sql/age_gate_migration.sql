-- 만 14세 self-declared 게이트 (한국 PIPA) — 2026-06-02.
-- ddl-auto=validate 라 엔티티 배포 전 선적용 필수.
-- prod: docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < age_gate_migration.sql
-- 생년월일 원문은 저장하지 않음 (privacy 최소화) — 확인값(boolean) + 확인시각만.

ALTER TABLE users ADD COLUMN IF NOT EXISTS is_over_14 BOOLEAN;
ALTER TABLE users ADD COLUMN IF NOT EXISTS age_checked_at TIMESTAMP;

-- 기존 온보딩 완료 유저 backfill — 출시 전 테스트 계정은 성인으로 가정(문서화된 전제).
-- changeNickname 의 isOver14 가드가 레거시 null 을 막지 않도록.
UPDATE users SET is_over_14 = TRUE, age_checked_at = COALESCE(age_checked_at, NOW())
  WHERE onboarded = TRUE AND is_over_14 IS NULL;
