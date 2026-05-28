-- Buy Order 양방향 채팅 마이그레이션 (2026-05-28)
-- 목적: BuyOrder(구매 호가) row에서도 채팅 시작 가능. 잠재 판매자가 구매 희망 작성자에게 채팅.
--
-- 설계 원칙:
--  - 가산형 변경: 기존 SALE chat 데이터/흐름 0 영향.
--  - 컬럼 명명 의미 일관: buyer_user_id = 카드 사려는 사람, seller_user_id = 카드 팔려는 사람.
--    SALE chat: buyer = 채팅 시작자, seller = TradePost.sellerId.
--    BUY chat:  buyer = BuyOrder.buyerId (작성자), seller = 채팅 시작자 (잠재 판매자).
--  - sale_listing_id 와 buy_order_id 는 정확히 하나만 NOT NULL (CHECK).
--
-- 적용 순서: 백엔드 코드 배포 전 prod psql 직접 실행.

BEGIN;

-- 1) sale_listing_id NULL 허용 (BUY chat에서는 NULL)
ALTER TABLE chat_rooms
    ALTER COLUMN sale_listing_id DROP NOT NULL;

-- 2) buy_order_id 컬럼 추가
ALTER TABLE chat_rooms
    ADD COLUMN IF NOT EXISTS buy_order_id VARCHAR(50);

-- 3) 기존 (sale_listing_id, buyer_user_id) unique 제거 (partial index로 교체).
--    JPA @UniqueConstraint 가 PostgreSQL 에선 CREATE UNIQUE INDEX 로 생성되므로
--    DROP CONSTRAINT 가 아니라 DROP INDEX 로 제거해야 함 (Codex 사전 리뷰 catch).
DROP INDEX IF EXISTS uq_chat_rooms_sale_buyer;
-- 안전망 — 환경에 따라 CONSTRAINT 로 생성됐을 가능성 대비 (no-op if not exists).
ALTER TABLE chat_rooms
    DROP CONSTRAINT IF EXISTS uq_chat_rooms_sale_buyer;

-- 4) SALE chat 용 partial unique — sale_listing_id NOT NULL row만
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_rooms_sale_buyer
    ON chat_rooms (sale_listing_id, buyer_user_id)
    WHERE sale_listing_id IS NOT NULL;

-- 5) BUY chat 용 partial unique — buy_order_id NOT NULL row만
--    한 BuyOrder당 한 명의 잠재 판매자 = 한 방.
CREATE UNIQUE INDEX IF NOT EXISTS uq_chat_rooms_buy_seller
    ON chat_rooms (buy_order_id, seller_user_id)
    WHERE buy_order_id IS NOT NULL;

-- 6) buy_order_id 조회용 일반 index (getMyRooms 등 lookup)
CREATE INDEX IF NOT EXISTS idx_chat_rooms_buy_order
    ON chat_rooms (buy_order_id)
    WHERE buy_order_id IS NOT NULL;

-- 7) XOR CHECK — sale_listing_id 와 buy_order_id 중 정확히 하나만 NOT NULL.
--    기존 SALE row는 sale_listing_id NOT NULL + buy_order_id NULL → 통과.
ALTER TABLE chat_rooms
    DROP CONSTRAINT IF EXISTS chk_chat_rooms_listing_xor;
ALTER TABLE chat_rooms
    ADD CONSTRAINT chk_chat_rooms_listing_xor
    CHECK (
        (sale_listing_id IS NOT NULL AND buy_order_id IS NULL)
        OR (sale_listing_id IS NULL AND buy_order_id IS NOT NULL)
    );

COMMIT;

-- 검증 쿼리 (적용 후 실행):
--   \d chat_rooms                                       -- buy_order_id 컬럼 + 새 인덱스 확인
--   SELECT COUNT(*) FROM chat_rooms WHERE sale_listing_id IS NULL;  -- 0이어야 (기존 데이터)
--   SELECT COUNT(*) FROM chat_rooms WHERE buy_order_id IS NOT NULL; -- 0이어야 (마이그레이션 직후)
