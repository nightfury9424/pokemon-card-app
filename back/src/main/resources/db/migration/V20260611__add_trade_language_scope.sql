-- 거래 발매판(언어) 분리: TradePost(매도)·BuyOrder(매수)에 language(KO/JP/EN) 추가.
-- 매도=자산 언어 상속 / 매수=구매자 선택 / 호가창 언어별 분리.
-- 2026-06-11. 기존 데이터 = trade_posts 1 / buy_orders 0 (테스트DB wipe 후) → 백필 trivial.

-- 1) 컬럼 추가 (먼저 nullable)
ALTER TABLE trade_posts ADD COLUMN IF NOT EXISTS language VARCHAR(10);
ALTER TABLE buy_orders  ADD COLUMN IF NOT EXISTS language VARCHAR(10);

-- 2) 백필: trade_posts ← assets.language → cards.language → 'KO'
UPDATE trade_posts tp SET language = COALESCE(
        (SELECT a.language FROM assets a WHERE a.asset_id = tp.asset_id),
        (SELECT c.language FROM cards  c WHERE c.card_id  = tp.card_id),
        'KO')
WHERE tp.language IS NULL;

-- buy_orders ← cards.language → 'KO' (현재 0건, no-op)
UPDATE buy_orders bo SET language = COALESCE(
        (SELECT c.language FROM cards c WHERE c.card_id = bo.card_id),
        'KO')
WHERE bo.language IS NULL;

-- 2.5) MULTI/비표준 언어 → KO (card.language='MULTI' 등이 CHECK 위반하지 않게)
UPDATE trade_posts SET language = 'KO' WHERE language IS NOT NULL AND language NOT IN ('KO','JP','EN');
UPDATE buy_orders  SET language = 'KO' WHERE language IS NOT NULL AND language NOT IN ('KO','JP','EN');

-- 3) NOT NULL + CHECK (KO/JP/EN 만)
ALTER TABLE trade_posts ALTER COLUMN language SET NOT NULL;
ALTER TABLE buy_orders  ALTER COLUMN language SET NOT NULL;
ALTER TABLE trade_posts ADD CONSTRAINT chk_trade_posts_language CHECK (language IN ('KO','JP','EN'));
ALTER TABLE buy_orders  ADD CONSTRAINT chk_buy_orders_language  CHECK (language IN ('KO','JP','EN'));

-- 4) 조회 인덱스 (card_id + language + status)
CREATE INDEX IF NOT EXISTS idx_trade_posts_card_lang_status ON trade_posts (card_id, language, status);
CREATE INDEX IF NOT EXISTS idx_buy_orders_card_lang_status  ON buy_orders  (card_id, language, status);

-- 5) 매수 중복 제약: (buyer,card,OPEN) → (buyer,card,language,OPEN)
--    같은 카드라도 KO/JP/EN 매수호가는 각각 1개씩 허용.
DROP INDEX IF EXISTS uq_buy_orders_buyer_card_open;
CREATE UNIQUE INDEX uq_buy_orders_buyer_card_lang_open
    ON buy_orders (buyer_id, card_id, language) WHERE status = 'OPEN';
