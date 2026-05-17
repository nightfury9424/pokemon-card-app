-- card_market_segment_overrides
-- Turn D-Round1 / market_segment_key 도입 (2026-05-17)
-- 카드별 manual override 또는 자동 감지 결과 저장.
-- resolveCoeffDetail priority chain:
--   CARD > MANUAL > SUPPORTER_DETECTED > AUTO_ACCEPT > era_rarity > rarity > global

CREATE TABLE IF NOT EXISTS card_market_segment_overrides (
    card_id            VARCHAR(50)  PRIMARY KEY,
    market_segment_key VARCHAR(80)  NOT NULL,
    segment_source     VARCHAR(50)  NOT NULL,
    created_at         TIMESTAMP    NOT NULL DEFAULT now(),
    updated_at         TIMESTAMP    NOT NULL DEFAULT now(),
    CONSTRAINT fk_cmso_card FOREIGN KEY (card_id) REFERENCES cards(card_id) ON DELETE CASCADE,
    -- VARCHAR + CHECK (PostgreSQL native enum 회피 — JPA @Enumerated(EnumType.STRING) 매핑 안전)
    CONSTRAINT chk_cmso_source CHECK (segment_source IN (
        'MANUAL',
        'AUTO_ACCEPT',
        'SUPPORTER_DETECTED',
        'SUPPORTER_DETECTED_FROM_MANUAL',
        'POKEMON_V_RESTORED'
    )),
    CONSTRAINT chk_cmso_segment_key CHECK (market_segment_key IN (
        -- SWSH (Turn D-Round1, 2026-05-17)
        'SWSH_SR_FULLART',
        'SWSH_SR_SPECIAL_ART',
        'SWSH_SR_SUPPORTER',
        'SWSH_HR_RAINBOW',
        'SWSH_HR_SPECIAL_ART',
        'SWSH_HR_SUPPORTER'
        -- 향후 SV/MEGA/SM 추가 시 ALTER TABLE DROP/ADD CONSTRAINT로 확장
    ))
);

CREATE INDEX IF NOT EXISTS idx_cmso_segment ON card_market_segment_overrides(market_segment_key);
CREATE INDEX IF NOT EXISTS idx_cmso_source ON card_market_segment_overrides(segment_source);

COMMENT ON TABLE card_market_segment_overrides IS 'market_segment_key override (manual or auto-detected). Turn D-Round1.';
COMMENT ON COLUMN card_market_segment_overrides.market_segment_key IS 'e.g. SWSH_SR_FULLART, SWSH_HR_SPECIAL_ART, SWSH_SR_SUPPORTER';
COMMENT ON COLUMN card_market_segment_overrides.segment_source IS 'MANUAL / AUTO_ACCEPT / SUPPORTER_DETECTED / SUPPORTER_DETECTED_FROM_MANUAL / POKEMON_V_RESTORED';
