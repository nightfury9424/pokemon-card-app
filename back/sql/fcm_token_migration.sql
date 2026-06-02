-- FCM 기기 푸시 토큰 저장 (2026-06-03). ddl-auto=validate 선행 실행.
-- prod: docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < fcm_token_migration.sql
CREATE TABLE IF NOT EXISTS fcm_tokens (
    token_id   VARCHAR(50) PRIMARY KEY,
    user_id    VARCHAR(50) NOT NULL,
    token      VARCHAR(500) NOT NULL UNIQUE,
    platform   VARCHAR(20),                       -- ios / android
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fcm_tokens_user ON fcm_tokens(user_id);
