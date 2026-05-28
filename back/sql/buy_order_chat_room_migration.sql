-- Buy Order 양방향 채팅 마이그레이션 (2026-05-28)
-- 목적: BuyOrder(구매 호가) row에서도 채팅 시작 가능.
--
-- ⚠ 2026-05-28 Codex 사후 리뷰 결정적 수정:
--   원본은 단일 트랜잭션 + non-concurrent CREATE/DROP INDEX 로 live table에 exclusive lock.
--   prod 적용 시 chat_rooms 모든 write 가 인덱스 빌드 시간만큼 차단.
--   해결: 각 step 을 분리 + CONCURRENTLY + NOT VALID/VALIDATE 패턴.
--
-- 적용 순서: psql 에서 step 별 실행 (CONCURRENTLY는 한 트랜잭션 안에서 동작 X).
--   psql -d pokemon_card_db -f buy_order_chat_room_migration.sql 한 번에 실행 X.
--   아래 step 코멘트 따라 한 줄/한 블록씩 실행.

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 1. 컬럼 변경 (짧은 ACCESS EXCLUSIVE — sub-second).
-- ─────────────────────────────────────────────────────────────────────────

ALTER TABLE chat_rooms
    ALTER COLUMN sale_listing_id DROP NOT NULL;

ALTER TABLE chat_rooms
    ADD COLUMN IF NOT EXISTS buy_order_id VARCHAR(50);

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 2. 새 partial unique index CONCURRENTLY 생성 (write 차단 X).
--          이름 충돌 회피 — 기존 'uq_chat_rooms_sale_buyer'(전체 unique) 와
--          새 partial(sale_listing_id NOT NULL 한정)은 의미가 다르므로 _v2 suffix.
-- ─────────────────────────────────────────────────────────────────────────

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_chat_rooms_sale_buyer_v2
    ON chat_rooms (sale_listing_id, buyer_user_id)
    WHERE sale_listing_id IS NOT NULL;

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_chat_rooms_buy_seller
    ON chat_rooms (buy_order_id, seller_user_id)
    WHERE buy_order_id IS NOT NULL;

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_chat_rooms_buy_order
    ON chat_rooms (buy_order_id)
    WHERE buy_order_id IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 3. (uq_chat_rooms_sale_buyer_v2 검증 후) 기존 전체-unique CONCURRENTLY drop.
--          v2 가 SALE 데이터에 대해 동등한 uniqueness 보장 (sale_listing_id NOT NULL row).
--          기존 데이터는 모두 sale_listing_id NOT NULL 이므로 transition gap 없음.
-- ─────────────────────────────────────────────────────────────────────────

DROP INDEX CONCURRENTLY IF EXISTS uq_chat_rooms_sale_buyer;

-- ─────────────────────────────────────────────────────────────────────────
-- STEP 4. XOR CHECK 추가 — NOT VALID 로 짧게 메타데이터만 박은 뒤 별도 VALIDATE.
--          NOT VALID 단계는 ACCESS EXCLUSIVE 가 짧고 기존 row 검증 skip.
--          VALIDATE 단계는 row 검증하지만 write 차단 X (SHARE UPDATE EXCLUSIVE).
-- ─────────────────────────────────────────────────────────────────────────

ALTER TABLE chat_rooms
    DROP CONSTRAINT IF EXISTS chk_chat_rooms_listing_xor;

ALTER TABLE chat_rooms
    ADD CONSTRAINT chk_chat_rooms_listing_xor
    CHECK (
        (sale_listing_id IS NOT NULL AND buy_order_id IS NULL)
        OR (sale_listing_id IS NULL AND buy_order_id IS NOT NULL)
    ) NOT VALID;

ALTER TABLE chat_rooms
    VALIDATE CONSTRAINT chk_chat_rooms_listing_xor;

-- ─────────────────────────────────────────────────────────────────────────
-- 검증 쿼리 (모든 step 후):
--   \d chat_rooms                                                    -- buy_order_id + 새 인덱스 확인
--   SELECT COUNT(*) FROM chat_rooms WHERE sale_listing_id IS NULL;   -- 0이어야 (기존 데이터)
--   SELECT COUNT(*) FROM chat_rooms WHERE buy_order_id IS NOT NULL;  -- 0이어야 (마이그레이션 직후)
--   SELECT indexname FROM pg_indexes WHERE tablename='chat_rooms';   -- 새 인덱스 3개 확인
-- ─────────────────────────────────────────────────────────────────────────
