-- ============================================================================
-- V20260529__add_price_anomalies_resolution_type.sql
-- ============================================================================
-- admin P0 #3 — 가격 이상 알림 처리 방식 구분 (REVIEWED vs DISMISSED).
--
-- 배경:
--  - 기존 price_anomalies 는 is_resolved (boolean) 만 보유.
--  - 운영자가 "검토 완료"(실제 검토 후 정상으로 판단)와 "무시"(중요하지 않다고 판단해 그냥 닫음)를
--    구분할 방법이 없어 추후 재검토/감사 시 의도 파악 불가.
--  - Codex 사전 검토 Q4: admin_actions audit 만으로 구분하면 join/parsing 의존 → schema 1 컬럼이 깔끔.
--
-- 컬럼:
--  - resolution_type VARCHAR(20) NULL
--      REVIEWED   = 운영자가 내용 검토 후 의도적으로 닫음
--      DISMISSED  = 운영자가 사유와 함께 무시 처리
--      NULL       = 기존 row 또는 미처리
--
-- 적용 방법 (prod):
--   docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db \
--     < V20260529__add_price_anomalies_resolution_type.sql
--
-- 적용 후 검증:
--   \d price_anomalies
--   → resolution_type | character varying(20) 컬럼 추가 확인
-- ============================================================================

ALTER TABLE price_anomalies
    ADD COLUMN IF NOT EXISTS resolution_type VARCHAR(20);

COMMENT ON COLUMN price_anomalies.resolution_type IS
    'admin 처리 방식 — REVIEWED(검토 후 닫음) / DISMISSED(무시) / NULL(미처리 또는 legacy)';
