-- =============================================================
-- 카드 단위 찜 마이그레이션 (2026-05-12)
-- 거래 리스트에서 하트 토글로 카드 찜. PostInterest(판매글 단위)와 별개.
-- =============================================================

CREATE TABLE IF NOT EXISTS card_interests (
    interest_id   VARCHAR(50) PRIMARY KEY,
    user_id       VARCHAR(50) NOT NULL,
    card_id       VARCHAR(50) NOT NULL,
    created_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, card_id)
);

CREATE INDEX IF NOT EXISTS idx_card_interests_user_id ON card_interests(user_id);
