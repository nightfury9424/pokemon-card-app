-- =============================================================
-- User blocks MVP migration
-- =============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS blocks (
    block_id VARCHAR(50) PRIMARY KEY,
    blocker_id VARCHAR(50) NOT NULL,
    blocked_id VARCHAR(50) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_blocks_blocker_blocked UNIQUE (blocker_id, blocked_id),
    CONSTRAINT chk_blocks_not_self CHECK (blocker_id <> blocked_id)
);

CREATE INDEX IF NOT EXISTS idx_blocks_blocker_id ON blocks (blocker_id);
CREATE INDEX IF NOT EXISTS idx_blocks_blocked_id ON blocks (blocked_id);

COMMIT;
