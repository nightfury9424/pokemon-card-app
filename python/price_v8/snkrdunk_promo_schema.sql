-- ════════════════════════════════════════════════════════════════════════
-- card_external_refs — 외부 ID 매핑 **보조** 테이블 (가격 원본 아님)
-- ════════════════════════════════════════════════════════════════════════
-- ★가격 원본 구조(price_snapshots)는 절대 변경하지 않는다.
--   SNKRDUNK 도 Scrydex 와 같은 price_snapshots 틀에 source='SNKRDUNK' 로 append-only 적재.
--   이 테이블은 오직 card_id ↔ SNKRDUNK apparel_id 연결용. SNK daily/backfill 이 이걸 보고
--   수집 대상 카드를 찾는다.
--
-- ★JPA 엔티티로 매핑하지 않는다 (Python 수집기 전용). ddl-auto: validate 는 매핑된 엔티티
--   컬럼만 검증 → 매핑 안 한 신규 테이블은 백엔드/validate 에 영향 0.
-- ★기존 price_snapshots / cards / products 에 영향 0 (신규 테이블만 생성. cards 로의 FK 는
--   이 테이블 쪽에만 걸리며 cards 를 ALTER 하지 않는다).

-- ── [적용 전 확인] 이미 있으면 no-op (IF NOT EXISTS) ──────────────────────
SELECT to_regclass('public.card_external_refs') AS already_exists;   -- NULL 이면 신규 생성됨

CREATE TABLE IF NOT EXISTS card_external_refs (
    id            BIGSERIAL     PRIMARY KEY,
    card_id       VARCHAR(50)   NOT NULL REFERENCES cards(card_id) ON DELETE CASCADE,
    source        VARCHAR(20)   NOT NULL,          -- 'SNKRDUNK' (향후 확장)
    external_id   VARCHAR(100)  NOT NULL,          -- SNKRDUNK apparel_id, 예: '618447'
    external_url  VARCHAR(500),                    -- 참고 URL
    is_active     BOOLEAN       NOT NULL DEFAULT TRUE,   -- 수집 대상 on/off (false 면 sync 제외)
    created_at    TIMESTAMP     NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_card_external_refs_source_extid UNIQUE (source, external_id),
    CONSTRAINT uq_card_external_refs_card_source  UNIQUE (card_id, source)
);

CREATE INDEX IF NOT EXISTS idx_card_external_refs_source_active
    ON card_external_refs (source, is_active);

-- ── [롤백] 신규 테이블이므로 통째 제거 (기존 데이터 영향 0) ────────────────
--   DROP TABLE IF EXISTS card_external_refs;
