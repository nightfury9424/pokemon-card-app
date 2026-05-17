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
    user_id              VARCHAR(50)  PRIMARY KEY,
    google_id            VARCHAR(100) NOT NULL UNIQUE,
    nickname             VARCHAR(50),
    email                VARCHAR(200),
    profile_image_url    VARCHAR(500),
    onboarded            BOOLEAN      NOT NULL DEFAULT FALSE,
    nickname_changed_at  TIMESTAMP,
    created_at           TIMESTAMP    NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMP    NOT NULL DEFAULT NOW()
);

-- 닉네임 lowercase unique (NULL은 중복 허용 — 온보딩 전 사용자)
CREATE UNIQUE INDEX users_nickname_lower_idx
    ON users (LOWER(nickname))
    WHERE nickname IS NOT NULL;

-- 제품/확장팩/덱/프로모 통합
CREATE TABLE products (
    product_id            VARCHAR(50)  PRIMARY KEY,
    name                  VARCHAR(200) NOT NULL,
    series_name           VARCHAR(200),
    product_type          VARCHAR(30),   -- BOOSTER / DECK / PROMO / SPECIAL ...
    language              VARCHAR(10)  NOT NULL, -- KO / JP / EN
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

    language              VARCHAR(10)  NOT NULL, -- KO / JP / EN
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
    grading_company       VARCHAR(20),           -- PSA / BRG
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
    language              VARCHAR(10) NOT NULL DEFAULT 'KO', -- KO / JP / EN (displayPrice 계산 기준)
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
-- 매수 호가 (BuyOrder = "삽니다") — 4차-Round4-4 Phase 1
-- 판매 호가(TradePost)와 양방향 호가창 구성. 채팅 기반 협상 (자동 매칭 X).
-- =============================================================
CREATE TABLE buy_orders (
    buy_order_id        VARCHAR(50) PRIMARY KEY,
    buyer_id            VARCHAR(50) NOT NULL,
    card_id             VARCHAR(50) NOT NULL,
    bid_price           INTEGER     NOT NULL,
    qty                 INTEGER     NOT NULL DEFAULT 1,
    card_status         VARCHAR(20) NOT NULL,            -- RAW / GRADED
    grading_company     VARCHAR(20),                     -- PSA / BGS / CGC (GRADED만)
    grade_value         VARCHAR(20),                     -- 10 / 9.5 / ... (GRADED만)
    memo                TEXT,
    status              VARCHAR(20) NOT NULL DEFAULT 'OPEN',  -- OPEN / MATCHED / CANCELED
    matched_trade_id    VARCHAR(50),                     -- 체결 시 연결된 거래
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_buy_orders_card_status_price
    ON buy_orders(card_id, status, bid_price DESC);
CREATE INDEX idx_buy_orders_buyer
    ON buy_orders(buyer_id, status);

-- 동일 사용자가 동일 카드에 OPEN 상태로 1개만
CREATE UNIQUE INDEX uq_buy_orders_buyer_card_open
    ON buy_orders(buyer_id, card_id)
    WHERE status = 'OPEN';

-- =============================================================
-- 알림 (4차-Round4-4 Phase 6 알림 시스템)
-- =============================================================
CREATE TABLE notifications (
    notification_id     VARCHAR(50) PRIMARY KEY,
    user_id             VARCHAR(50) NOT NULL,
    type                VARCHAR(40) NOT NULL,        -- BUY_ORDER_ON_MY_CARD / TRADE_ON_MY_BUY_ORDER / ...
    title               VARCHAR(120) NOT NULL,
    body                TEXT,
    link_card_id        VARCHAR(50),                 -- 클릭 시 카드 상세로 이동
    link_url            VARCHAR(255),                -- 또는 임의 URL
    is_read             BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_unread
    ON notifications(user_id, is_read, created_at DESC);

-- =============================================================
-- 신고 (4차-Round4-5 거래/사용자/매수호가 신고)
-- =============================================================
CREATE TABLE reports (
    report_id           VARCHAR(50) PRIMARY KEY,
    reporter_id         VARCHAR(50) NOT NULL,
    target_type         VARCHAR(20) NOT NULL,            -- TRADE / USER / BUY_ORDER / CHAT
    target_id           VARCHAR(50) NOT NULL,
    reason              VARCHAR(40) NOT NULL,            -- FRAUD / FAKE / ABUSIVE_PRICE / INSULT / SPAM / OTHER
    detail              TEXT,
    status              VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING / REVIEWED / RESOLVED / DISMISSED
    created_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    reviewed_at         TIMESTAMP
);

CREATE INDEX idx_reports_target ON reports(target_type, target_id);
CREATE INDEX idx_reports_reporter ON reports(reporter_id);
CREATE INDEX idx_reports_status ON reports(status, created_at DESC);

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

-- 환율 race condition 방지 (REFACTOR_2026-05-12.md 3차-B, Codex WARN #1)
-- 카드별 하루 1건만 허용 — Java/Python 동시 INSERT 시 두 row 생기는 사고 차단
CREATE UNIQUE INDEX IF NOT EXISTS idx_ps_system_exchange_rate_one_per_day
  ON price_snapshots (card_id, DATE(traded_at))
  WHERE source = 'SYSTEM' AND card_id IN ('exchange_rate_usd', 'exchange_rate_jpy');

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

-- =============================================================
-- 카드 단위 찜 (관심 목록) — 거래 리스트에서 하트 토글
-- 판매글 단위 찜(post_interests)과 별개
-- =============================================================
CREATE TABLE card_interests (
    interest_id   VARCHAR(50) PRIMARY KEY,
    user_id       VARCHAR(50) NOT NULL,
    card_id       VARCHAR(50) NOT NULL,
    created_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
    UNIQUE (user_id, card_id)
);
CREATE INDEX idx_card_interests_user_id ON card_interests(user_id);
