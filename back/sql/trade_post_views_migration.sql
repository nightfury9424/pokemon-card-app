-- trade_post_views: 1인 1조회 정책. 같은 user가 같은 trade를 여러 번 봐도 view 1회만 카운트.
-- 판매자가 자기 글 보는 건 backend에서 skip (sellerId == viewerUserId).
-- prod 배포 전 적용 필수 — ddl-auto=validate.

CREATE TABLE IF NOT EXISTS trade_post_views (
    view_id    VARCHAR(36) PRIMARY KEY,
    trade_id   VARCHAR(36) NOT NULL,
    user_id    VARCHAR(36) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_trade_post_views_trade_user
    ON trade_post_views (trade_id, user_id);

CREATE INDEX IF NOT EXISTS idx_trade_post_views_trade
    ON trade_post_views (trade_id);
