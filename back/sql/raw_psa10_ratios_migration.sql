-- PR-RATIO: PSA10 -> RAW 환산 비율 저장.
-- (source, rarity)별 median(RAW/PSA10) 매일 자동 계산.
-- PSA10만 있는 카드의 RAW 추정에 사용해 KO 예상가 흐름 재사용 가능하게 함.

CREATE TABLE IF NOT EXISTS raw_psa10_ratios (
    source        VARCHAR(20)    NOT NULL,
    rarity_code   VARCHAR(20)    NOT NULL,
    window_days   INT            NOT NULL,
    sample_count  INT            NOT NULL,
    ratio_median  NUMERIC(8,5)   NOT NULL,
    ratio_p25     NUMERIC(8,5),
    ratio_p75     NUMERIC(8,5),
    computed_at   TIMESTAMP      NOT NULL DEFAULT NOW(),
    PRIMARY KEY (source, rarity_code)
);

CREATE INDEX IF NOT EXISTS idx_raw_psa10_ratios_computed_at
    ON raw_psa10_ratios (computed_at DESC);

COMMENT ON TABLE raw_psa10_ratios IS
    'PSA10 가격에서 RAW 가격 추정용 비율 (source × rarity). 매일 cron 갱신.';
COMMENT ON COLUMN raw_psa10_ratios.ratio_median IS
    'RAW/PSA10 비율 중앙값. PSA10 × ratio_median = 추정 RAW.';
COMMENT ON COLUMN raw_psa10_ratios.sample_count IS
    '계산에 사용된 paired card 수 (RAW + PSA10 둘 다 있는 카드).';
