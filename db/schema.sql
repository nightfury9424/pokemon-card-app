-- =============================================================
-- 포켓몬 카드 앱 DB Schema
-- DB: PostgreSQL
-- Version: 3.0
-- Style: VARCHAR PK + Java ID 생성 + FK 미사용
-- =============================================================

-- =============================================================
-- 1차 도메인
-- =============================================================

-- 사용자
CREATE TABLE users (
    user_id            VARCHAR(50)  PRIMARY KEY,
    kakao_id           VARCHAR(100) NOT NULL UNIQUE,
    nickname           VARCHAR(50)  NOT NULL,
    profile_image_url  VARCHAR(500),
    created_at         TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 제품/확장팩/덱/프로모 통합
CREATE TABLE products (
    product_id            VARCHAR(50)  PRIMARY KEY,
    name                  VARCHAR(200) NOT NULL,
    series_name           VARCHAR(200),
    product_type          VARCHAR(30),   -- BOOSTER / DECK / PROMO / SPECIAL ...
    language              VARCHAR(10)  NOT NULL, -- KO / JA / EN
    image_url             VARCHAR(500),
    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 카드 마스터
CREATE TABLE cards (
    card_id               VARCHAR(50)  PRIMARY KEY,
    product_id            VARCHAR(50)  NOT NULL,

    official_card_code    VARCHAR(100),
    name                  VARCHAR(200) NOT NULL,

    collection_number     VARCHAR(50),   -- ex: 001/165
    card_number           VARCHAR(50),
    rarity_code           VARCHAR(50),   -- nullable

    language              VARCHAR(10)  NOT NULL, -- KO / JA / EN
    super_type            VARCHAR(30)  NOT NULL, -- POKEMON / TRAINER / ENERGY
    sub_type              VARCHAR(50),           -- ITEM / SUPPORTER / STADIUM / TOOL / BASIC / SPECIAL ...
    illustrator           VARCHAR(100),
    image_url             VARCHAR(500),
    official_url          VARCHAR(500),

    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 시세 원천 데이터 (당근 / 번개장터 / icu.gg 수집)
CREATE TABLE price_snapshots (
    price_snapshot_id     VARCHAR(50)  PRIMARY KEY,
    card_id               VARCHAR(50)  NOT NULL,

    source                VARCHAR(20)  NOT NULL, -- DAANGN / BUNJANG / ICU
    source_item_id        VARCHAR(100),
    source_url            VARCHAR(500),

    price                 INTEGER      NOT NULL CHECK (price > 0),
    currency              VARCHAR(10)  NOT NULL DEFAULT 'KRW',

    card_status           VARCHAR(20)  NOT NULL, -- RAW / GRADED
    grading_company       VARCHAR(20),           -- PSA / BGS / CGC / OTHER
    grade_value           VARCHAR(20),           -- 10 / 9.5 ...
    cert_number           VARCHAR(100),

    traded_at             TIMESTAMP NOT NULL,
    collected_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    created_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 시세 집계 (7D / 30D 캐싱 - API 응답 속도 최적화)
CREATE TABLE price_summaries (
    price_summary_id      VARCHAR(50) PRIMARY KEY,
    card_id               VARCHAR(50) NOT NULL,

    card_status           VARCHAR(20) NOT NULL, -- RAW / GRADED
    grading_company       VARCHAR(20),
    grade_value           VARCHAR(20),

    period                VARCHAR(10) NOT NULL, -- 7D / 30D
    median_price          INTEGER,
    avg_price             INTEGER,
    min_price             INTEGER,
    max_price             INTEGER,
    trade_count           INTEGER NOT NULL DEFAULT 0,
    calculated_at         TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 사용자 자산
CREATE TABLE assets (
    asset_id              VARCHAR(50) PRIMARY KEY,
    user_id               VARCHAR(50) NOT NULL,
    card_id               VARCHAR(50) NOT NULL,

    quantity              INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
    purchase_price        INTEGER CHECK (purchase_price >= 0),

    card_status           VARCHAR(20) NOT NULL, -- RAW / GRADED
    grading_company       VARCHAR(20),
    grade_value           VARCHAR(20),
    cert_number           VARCHAR(100),

    memo                  TEXT,
    purchased_at          DATE,

    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =============================================================
-- 2차 도메인
-- =============================================================

-- 판매 등록
CREATE TABLE sale_listings (
    sale_listing_id       VARCHAR(50) PRIMARY KEY,
    asset_id              VARCHAR(50) NOT NULL,

    sale_quantity         INTEGER NOT NULL DEFAULT 1 CHECK (sale_quantity > 0),
    desired_price         INTEGER CHECK (desired_price >= 0),
    memo                  TEXT,

    is_public             BOOLEAN NOT NULL DEFAULT FALSE,
    sale_status           VARCHAR(20) NOT NULL DEFAULT 'OPEN', -- OPEN / CLOSED / RESERVED

    created_at            TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 채팅방
CREATE TABLE chat_rooms (
    chat_room_id          VARCHAR(50) PRIMARY KEY,
    sale_listing_id       VARCHAR(50) NOT NULL,
    seller_user_id        VARCHAR(50) NOT NULL,
    buyer_user_id         VARCHAR(50) NOT NULL,
    created_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 채팅 메시지
CREATE TABLE chat_messages (
    chat_message_id       VARCHAR(50) PRIMARY KEY,
    chat_room_id          VARCHAR(50) NOT NULL,
    sender_user_id        VARCHAR(50) NOT NULL,
    message               TEXT        NOT NULL,
    created_at            TIMESTAMP NOT NULL DEFAULT NOW()
);

-- =============================================================
-- 유니크 제약
-- =============================================================

-- 같은 제품 내 카드 번호 중복 방지
CREATE UNIQUE INDEX uq_cards_product_collection
    ON cards(product_id, collection_number);

-- 시세 집계 중복 방지
CREATE UNIQUE INDEX uq_price_summaries_key
    ON price_summaries(card_id, card_status, grading_company, grade_value, period);

-- =============================================================
-- 인덱스 (대량 조회 기준으로만 추가)
-- =============================================================

-- 제품
CREATE INDEX idx_products_language      ON products(language);
CREATE INDEX idx_products_series_name   ON products(series_name);

-- 카드
CREATE INDEX idx_cards_product_id        ON cards(product_id);
CREATE INDEX idx_cards_name              ON cards(name);
CREATE INDEX idx_cards_language          ON cards(language);
CREATE INDEX idx_cards_super_type        ON cards(super_type);
CREATE INDEX idx_cards_sub_type          ON cards(sub_type);
CREATE INDEX idx_cards_collection_number ON cards(collection_number);

-- 시세
CREATE INDEX idx_price_snapshots_card_id    ON price_snapshots(card_id);
CREATE INDEX idx_price_snapshots_source     ON price_snapshots(source);
CREATE INDEX idx_price_snapshots_traded_at  ON price_snapshots(traded_at DESC);
CREATE INDEX idx_price_snapshots_card_status ON price_snapshots(card_status);
CREATE INDEX idx_price_snapshots_grade      ON price_snapshots(grading_company, grade_value);

-- 자산
CREATE INDEX idx_assets_user_id     ON assets(user_id);
CREATE INDEX idx_assets_card_id     ON assets(card_id);
CREATE INDEX idx_assets_card_status ON assets(card_status);

-- 판매
CREATE INDEX idx_sale_listings_asset_id    ON sale_listings(asset_id);
CREATE INDEX idx_sale_listings_is_public   ON sale_listings(is_public);
CREATE INDEX idx_sale_listings_sale_status ON sale_listings(sale_status);

-- 채팅
CREATE INDEX idx_chat_rooms_seller_user_id    ON chat_rooms(seller_user_id);
CREATE INDEX idx_chat_rooms_buyer_user_id     ON chat_rooms(buyer_user_id);
CREATE INDEX idx_chat_messages_chat_room_id   ON chat_messages(chat_room_id);
CREATE INDEX idx_chat_messages_created_at     ON chat_messages(created_at DESC);
