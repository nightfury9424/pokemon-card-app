-- Sign in with Apple 추가 — google_id nullable + apple_id 컬럼. ddl-auto=validate 선행 실행.
-- prod: docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < apple_login_migration.sql
ALTER TABLE users ALTER COLUMN google_id DROP NOT NULL;
ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_id VARCHAR(100);
CREATE UNIQUE INDEX IF NOT EXISTS uq_users_apple_id ON users(apple_id);
