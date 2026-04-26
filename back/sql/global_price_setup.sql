-- 1. cards 테이블에 TCGPlayer 카드 ID 컬럼 추가
ALTER TABLE cards ADD COLUMN IF NOT EXISTS tcgplayer_card_id VARCHAR(100);

-- 2. 제품(세트) ↔ pokemontcg.io 세트 ID 매핑 테이블
CREATE TABLE IF NOT EXISTS ptcg_set_mappings (
    product_id  VARCHAR(50) PRIMARY KEY,
    ptcg_set_id VARCHAR(50) NOT NULL,
    created_at  TIMESTAMP   NOT NULL DEFAULT NOW()
);
