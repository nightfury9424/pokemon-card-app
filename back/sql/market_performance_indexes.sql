-- Run each statement outside a transaction.
-- Main RAW latest-price LATERAL/source-IN pattern:
-- CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ps_card_source_traded
--   ON price_snapshots (card_id, source, traded_at DESC)
--   WHERE card_status = 'RAW';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ps_ko_estimated_card_traded
    ON price_snapshots (card_id, traded_at DESC)
    WHERE source = 'KO_ESTIMATED';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ps_system_coef_card_traded
    ON price_snapshots (card_id, traded_at DESC)
    WHERE source = 'SYSTEM' AND card_id LIKE 'ko_coef_%';

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ps_scrydex_jp_any_card_traded_price
    ON price_snapshots (card_id, traded_at DESC, price ASC)
    WHERE source = 'SCRYDEX_JP';
