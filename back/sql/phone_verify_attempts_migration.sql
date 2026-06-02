-- 2026-06-03 휴대폰 OTP 요청 rate limit 추적 테이블. ddl-auto=validate → 배포 전 prod 적용.
-- 적용: docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < phone_verify_attempts_migration.sql

CREATE TABLE IF NOT EXISTS phone_verify_attempts (
    attempt_id VARCHAR(50)  PRIMARY KEY,
    phone_e164 VARCHAR(20)  NOT NULL,
    user_id    VARCHAR(50),
    ip         VARCHAR(64),
    created_at TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_pva_phone_created ON phone_verify_attempts (phone_e164, created_at);
CREATE INDEX IF NOT EXISTS idx_pva_ip_created    ON phone_verify_attempts (ip, created_at);
CREATE INDEX IF NOT EXISTS idx_pva_user_created  ON phone_verify_attempts (user_id, created_at);
