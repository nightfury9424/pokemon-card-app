-- ════════════════════════════════════════════════════════════════════════
-- Phase 1 · 후쿠오카의 피카츄 (SV-P 289) 등록 — 메타몽 프로모 방식
-- ════════════════════════════════════════════════════════════════════════
-- ★★DEPRECATED (1장 수동 hotfix). 정식 경로 = import_snkrdunk_promo_cards.py
--   (SNK 후보 → 중복검사 → products/cards/card_external_refs 일괄 생성, 확장 가능).
--   이 파일은 참고/비상용으로만 남김. 신규 프로모는 import-list.csv 에 한 줄 추가 후 importer 실행.
-- ════════════════════════════════════════════════════════════════════════
-- 문의: "후쿠시마 피카츄"(오기) → 실제 = フクオカのピカチュウ P / SV-P 289 /
--       스페셜BOX「ポケモンセンターフクオカ」 / SNKRDUNK apparel_id=618447
-- scrydex 없음(svp_ja-289 = 404) → NO_JP/NO_EN, SNKRDUNK 일일 동기화로 시세.
--
-- ★실행 전 필수: card_external_refs 테이블 생성(snkrdunk_promo_schema.sql) 선행.
-- ★prod write — 반드시 아래 [백업] 먼저 뜨고, [검증] 확인 후, 승인 하에 실행.

-- ─────────────────────────────────────────────────────────────────────
-- [백업] 실행 전 상태 캡처 (충돌/롤백 대비)
-- ─────────────────────────────────────────────────────────────────────
-- \copy (SELECT * FROM cards       WHERE official_card_code='SVP000000289') TO 'bak_card_fukuoka.csv' CSV HEADER;
-- \copy (SELECT * FROM products    WHERE product_id='PRD_2650137AB4E54E229564') TO 'bak_product_fukuoka.csv' CSV HEADER;
SELECT COUNT(*) AS dup_code FROM cards WHERE official_card_code = 'SVP000000289';   -- 0 이어야 함

BEGIN;

-- 1) 세트(product) 신규
INSERT INTO products (product_id, name, series_name, language, created_at, updated_at)
VALUES ('PRD_2650137AB4E54E229564',
        '스칼렛&바이올렛 「포켓몬센터 후쿠오카」 스페셜 BOX',
        '', 'KO', NOW(), NOW());

-- 2) 카드 (메타몽 SVP000000173 관례 복제 · is_promo_exclusive=TRUE 핵심)
INSERT INTO cards
    (card_id, product_id, official_card_code, name, collection_number,
     rarity_code, language, super_type, jp_scrydex_ref, en_scrydex_ref,
     is_promo_exclusive, promo_type, image_url, local_image_path,
     is_visible, created_at, updated_at)
VALUES
    ('CRD_9BBB52C744B94B169A74', 'PRD_2650137AB4E54E229564', 'SVP000000289',
     '후쿠오카의 피카츄', NULL,
     'PR', 'KO', 'POKEMON', 'NO_JP', 'NO_EN',
     TRUE, 'POKEMON_CENTER', NULL, NULL,
     TRUE, NOW(), NOW());

-- 3) SNKRDUNK 매핑 (일일 동기화 대상 등록 · is_active=TRUE 여야 sync 대상)
INSERT INTO card_external_refs (card_id, source, external_id, external_url, is_active)
VALUES ('CRD_9BBB52C744B94B169A74', 'SNKRDUNK', '618447',
        'https://snkrdunk.com/v1/apparels/618447', TRUE);

-- 검증 후 COMMIT / 이상 시 ROLLBACK
-- COMMIT;

-- ─────────────────────────────────────────────────────────────────────
-- [최초 시세 시드]  — 커밋 후 아래로 첫 KO_ESTIMATED 채움 (이후 cron 이 매일 갱신)
--   python sync_snkrdunk_promo_prices.py --apply --card-id CRD_9BBB52C744B94B169A74
--   (RAW median ¥16,500 × 환율 ≈ ₩153,000)
-- ─────────────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────────────
-- [롤백]
--   DELETE FROM price_snapshots  WHERE card_id='CRD_9BBB52C744B94B169A74';
--   DELETE FROM card_external_refs WHERE card_id='CRD_9BBB52C744B94B169A74';
--   DELETE FROM cards            WHERE card_id='CRD_9BBB52C744B94B169A74';
--   DELETE FROM products         WHERE product_id='PRD_2650137AB4E54E229564';
-- ─────────────────────────────────────────────────────────────────────
