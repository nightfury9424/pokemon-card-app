-- 2026-05-30 도감 hits override (Cycle 2)
-- products.dex_hit_card_ids: CSV (CRD_xxx,CRD_yyy,...). NULL = 자동 fallback.
-- 백엔드 DexService 가 NULL/blank 이면 기존 rarity priority + collection_number top 4 사용.
-- 사용자 검수 (hits_picks_v3.md/json) + 수동 보정 7 시리즈 별 UPDATE 로 채움.
-- 컬렉션형 시리즈 (VSTAR / 테라스탈 / 151 / VMAX 클라이맥스) 최대 6장 허용.

ALTER TABLE products ADD COLUMN IF NOT EXISTS dex_hit_card_ids text;

COMMENT ON COLUMN products.dex_hit_card_ids IS
    '도감 힛카드 CSV override (순서 = display 순서, max 6). NULL = 자동 fallback (rarity priority + collection_number top 4).';
