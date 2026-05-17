-- Clear the incorrect scrydex JP mapping for Kanazawa Pikachu 2.
--
-- Reason:
--   jp_scrydex_ref = 'svp_ja-147' resolves on scrydex, but it is not
--   Kanazawa Pikachu 2. It points to a trainer card, so the mapping must be
--   treated as unknown until a matching ref is found.
--
-- Run manually after review, for example:
--   psql -h localhost -p 5432 -U nightfury -d pokemon_card_db \
--     -f back/sql/fix_kanazawa_pikachu_2_scrydex_ref.sql

BEGIN;

UPDATE cards
SET jp_scrydex_ref = NULL,
    updated_at = NOW()
WHERE is_promo_exclusive = TRUE
  AND name = '카나자와 피카츄 2'
  AND jp_scrydex_ref = 'svp_ja-147'
  AND collection_number IN ('147/SV-P', '147/S-P');

SELECT card_id, name, collection_number, jp_scrydex_ref, en_scrydex_ref
FROM cards
WHERE is_promo_exclusive = TRUE
  AND name = '카나자와 피카츄 2';

COMMIT;
