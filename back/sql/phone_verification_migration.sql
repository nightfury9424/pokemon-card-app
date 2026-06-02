-- 2026-06-03 휴대폰 OTP 인증 (Firebase Phone Auth) — users 컬럼 추가.
-- ddl-auto=validate 라 배포 전 prod 에 먼저 적용해야 함 (컬럼 없으면 컨테이너 부팅 실패).
-- 적용: docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < phone_verification_migration.sql

ALTER TABLE users
  ADD COLUMN IF NOT EXISTS phone_verified    BOOLEAN     NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS phone_e164        VARCHAR(20),
  ADD COLUMN IF NOT EXISTS phone_verified_at TIMESTAMP;

-- 한 번호당 인증 계정 1개만 (미인증/NULL 다중 허용). 중복 명의 도용 방지.
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_phone_e164_verified
  ON users (phone_e164)
  WHERE phone_verified = TRUE;
