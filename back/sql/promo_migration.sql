-- 프로모 카드 기능 마이그레이션
-- 실행 순서: 1 → 2 → 3 순서대로 실행

-- 1. cards 테이블 컬럼 추가 (없으면 추가)
ALTER TABLE cards ADD COLUMN IF NOT EXISTS is_promo_exclusive BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE cards ADD COLUMN IF NOT EXISTS promo_type VARCHAR(30);
ALTER TABLE cards ADD COLUMN IF NOT EXISTS en_scrydex_ref VARCHAR(100);
ALTER TABLE cards ADD COLUMN IF NOT EXISTS jp_scrydex_ref VARCHAR(200);

-- 2. JP_PROMO_EXCLUSIVE product row 생성
INSERT INTO products (product_id, name, series_name, product_type, language, created_at, updated_at)
VALUES ('JP_PROMO_EXCLUSIVE', 'JP 프로모 독점', 'PROMO', 'PROMO', 'JP', NOW(), NOW())
ON CONFLICT (product_id) DO NOTHING;

-- 3. 검증: 컬럼 존재 확인
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'cards'
  AND column_name IN ('is_promo_exclusive', 'promo_type', 'en_scrydex_ref', 'jp_scrydex_ref')
ORDER BY column_name;
