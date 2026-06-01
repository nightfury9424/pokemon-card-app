#!/bin/bash
# A4-extreme sanity cap — release D-5 임시 outlier 방어
# 정책: 일반 카드 ko_price > min(JP×jp_p75, EN×en_p75) × 3.0 → cap_value = min(...) × 1.0
# Created: 2026-05-27
# Remove after: release 후 DAANGN+PriceCharting 통합 모델 적용 (D+7~)

set -e
LOG=/opt/pokefolio/data/logs/sanity_cap_$(date +%Y%m%d).log
exec >>"$LOG" 2>&1
echo "=== $(date -Iseconds) sanity_cap start ==="

/usr/bin/docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db <<'SQL'
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE upd_count INT;
BEGIN
  WITH held AS (
    SELECT unnest(ARRAY[
      'CRD_692B14B6D94747048405','CRD_1AA5792C99D94054AB63',
      'CRD_C29D97F59E3E4E9FB4E0','CRD_92F7CF802A46497BBC5F',
      'CRD_7C974FE36E964EB996DB','CRD_3B37F7C8EEF44621A6E1',
      'CRD_9C70464E838941DB8DF0','CRD_9D5269AF1A2A42B4A293',
      'CRD_4A61E9FAD7D64AE2BB13','CRD_D7B1A8152CB241248591',
      'CRD_8C8EEF4E7290462E9827','CRD_05EA83500DDE4FE39A00',
      'CRD_939CD60D0A3F433EA9AD','CRD_D65DE41A73AB4B91B33B']) AS card_id
  ),
  cap_table AS (
    SELECT rarity_code, jp_p75, en_p75 FROM (VALUES
      ('HR'::varchar,  0.272::numeric, 0.258::numeric),
      ('AR',  0.362, 0.114),
      ('PR',  0.723, 0.980),
      ('MA',  0.420, 0.290),
      ('SAR', 0.422, 0.362),
      ('BWR', 0.388, 0.208),
      ('SR',  0.805, 0.964),
      ('RR',  0.846, 0.401),
      ('MUR', 0.468, 0.447),
      ('UR',  1.192, 0.728)
    ) AS r(rarity_code, jp_p75, en_p75)
  ),
  ko_today AS (
    SELECT ps.price_snapshot_id, ps.card_id, ps.price AS ko_price
    FROM price_snapshots ps JOIN cards c ON c.card_id=ps.card_id
    WHERE ps.source='KO_ESTIMATED' AND ps.traded_at::date=CURRENT_DATE
      AND c.is_promo_exclusive=false
      AND ps.card_id NOT IN (SELECT card_id FROM held)
  ),
  en_l AS (SELECT DISTINCT ON (card_id) card_id, price AS en_krw FROM price_snapshots
    WHERE source='SCRYDEX_EN' AND card_status='RAW'
      AND traded_at::date >= CURRENT_DATE - 7 AND price < 5000000
    ORDER BY card_id, traded_at DESC),
  jp_l AS (SELECT DISTINCT ON (card_id) card_id, price AS jp_krw FROM price_snapshots
    WHERE source='SCRYDEX_JP' AND card_status='RAW'
      AND traded_at::date >= CURRENT_DATE - 7 AND price < 5000000
    ORDER BY card_id, traded_at DESC),
  caps AS (
    SELECT k.price_snapshot_id, k.card_id, k.ko_price,
      LEAST(NULLIF((jp.jp_krw * r.jp_p75)::int, 0),
            NULLIF((en.en_krw * r.en_p75)::int, 0)) AS cap_value
    FROM ko_today k JOIN cards c USING (card_id)
    LEFT JOIN en_l en USING (card_id) LEFT JOIN jp_l jp USING (card_id)
    LEFT JOIN cap_table r ON r.rarity_code=c.rarity_code
  )
  UPDATE price_snapshots curr SET price = caps.cap_value
  FROM caps
  WHERE curr.price_snapshot_id = caps.price_snapshot_id
    AND caps.cap_value IS NOT NULL AND caps.cap_value > 0
    AND caps.ko_price > caps.cap_value * 3.0;
  GET DIAGNOSTICS upd_count = ROW_COUNT;
  RAISE NOTICE 'sanity cap updated: %', upd_count;
  IF upd_count > 600 THEN RAISE EXCEPTION 'too many: %', upd_count; END IF;
END $$;
COMMIT;
SQL

echo "=== $(date -Iseconds) sanity_cap done ==="
