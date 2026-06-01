-- 신고 1회 제한 — 신고된 사용자 id 저장 (reporter+target_user dedup). ddl-auto=validate 선행 실행.
-- prod: docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < reports_target_user_migration.sql
ALTER TABLE reports ADD COLUMN IF NOT EXISTS target_user_id VARCHAR(50);
CREATE INDEX IF NOT EXISTS idx_reports_reporter_target_user
    ON reports(reporter_id, target_user_id);
