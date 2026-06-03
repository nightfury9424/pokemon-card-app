-- 실거래가 수집 (APP_TRADE 원천 데이터). 거래 완료 후 양쪽 당사자가 실제 거래 금액 기입.
-- (trade_id, user_id) UNIQUE — 1인 1입력(재입력 시 update). 시세 반영은 후속 배치(여기선 수집만).
CREATE TABLE IF NOT EXISTS trade_settlements (
    settlement_id   VARCHAR(50)  PRIMARY KEY,
    trade_id        VARCHAR(50)  NOT NULL,
    user_id         VARCHAR(50)  NOT NULL,
    role            VARCHAR(10)  NOT NULL,
    card_id         VARCHAR(50),
    reported_price  INTEGER      NOT NULL,
    created_at      TIMESTAMP    NOT NULL DEFAULT now(),
    updated_at      TIMESTAMP,
    CONSTRAINT uq_trade_settlement_trade_user UNIQUE (trade_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_trade_settlement_trade ON trade_settlements (trade_id);
CREATE INDEX IF NOT EXISTS idx_trade_settlement_card  ON trade_settlements (card_id);
