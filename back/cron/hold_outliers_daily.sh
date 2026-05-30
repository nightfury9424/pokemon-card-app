#!/bin/bash
# Daily hold for SCRYDEX outlier cards (currency parse / eBay scrape mismatch 등)
# Created: 2026-05-26 (v1, 14 hardcoded)
# Updated: 2026-05-31 (v2 — 동적 count + 2 카드 추가 + is_visible/snapshot 가드)
#
# v2 변경:
#   - count 하드코딩 14 제거 → array length + visible/today snapshot 기준 동적 target_count
#   - 두빅굴 EX RR (xy3_ja-20) + 차곡차곡 GX SR (sm7_ja-99) 추가
#     (scrydex eBay scrape mismatch — 통화 단위/가격 자체 비정상 변동)
#   - is_visible=FALSE 카드 자동 skip
#   - 오늘 snapshot 없는 카드 skip
#   - upd_count 가 0~target_count 범위면 정상
#   - target_count 초과 시 에러 (예상치 못한 mass update 차단)

set -e
LOG=/opt/pokefolio/data/logs/hold_outliers_$(date +%Y%m%d).log
exec >>"$LOG" 2>&1
echo "=== $(date -Iseconds) hold start ==="

/usr/bin/docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db <<'SQL'
\set ON_ERROR_STOP on
BEGIN;
DO $$
DECLARE
  upd_count    INT;
  target_count INT;
  target_ids   text[] := ARRAY[
    -- v1 14 카드 (SCRYDEX JP currency parse 버그 outlier)
    'CRD_692B14B6D94747048405','CRD_1AA5792C99D94054AB63',
    'CRD_C29D97F59E3E4E9FB4E0','CRD_92F7CF802A46497BBC5F',
    'CRD_7C974FE36E964EB996DB','CRD_3B37F7C8EEF44621A6E1',
    'CRD_9C70464E838941DB8DF0','CRD_9D5269AF1A2A42B4A293',
    'CRD_4A61E9FAD7D64AE2BB13','CRD_D7B1A8152CB241248591',
    'CRD_8C8EEF4E7290462E9827','CRD_05EA83500DDE4FE39A00',
    'CRD_939CD60D0A3F433EA9AD','CRD_D65DE41A73AB4B91B33B',
    -- v2 추가 (scrydex eBay scrape mismatch, 2026-05-31)
    'CRD_43184344379E4533B6E5',  -- 두빅굴 EX RR (xy3_ja-20)
    'CRD_4CE79903A8A042498E53'   -- 차곡차곡 GX SR (sm7_ja-99)
  ];
BEGIN
  -- 동적 target_count: array 안 카드 중 visible=TRUE + 오늘 KO snapshot 존재만
  SELECT COUNT(DISTINCT c.card_id) INTO target_count
  FROM cards c
  JOIN price_snapshots ps
    ON ps.card_id = c.card_id
   AND ps.source = 'KO_ESTIMATED'
   AND ps.traded_at::date = CURRENT_DATE
  WHERE c.card_id = ANY(target_ids)
    AND c.is_visible = TRUE;

  -- 어제 안정값 → 오늘 carry
  UPDATE price_snapshots curr SET price = stable.price
  FROM (
    SELECT DISTINCT ON (card_id) card_id, price
    FROM price_snapshots
    WHERE source = 'KO_ESTIMATED'
      AND traded_at::date < CURRENT_DATE
      AND card_id = ANY(target_ids)
    ORDER BY card_id, traded_at DESC
  ) stable
  WHERE curr.card_id = stable.card_id
    AND curr.source = 'KO_ESTIMATED'
    AND curr.traded_at::date = CURRENT_DATE;

  GET DIAGNOSTICS upd_count = ROW_COUNT;
  RAISE NOTICE 'updated rows: %, target_count: %', upd_count, target_count;

  -- 0 ~ target_count = 정상 (carry 대상 일부 없을 수 있음 — visible/snapshot 가드)
  -- target_count 초과 = 예상치 못한 mass update (안전 가드)
  IF upd_count > target_count THEN
    RAISE EXCEPTION 'upd_count (%) > target_count (%) — unexpected mass update', upd_count, target_count;
  END IF;
END $$;
COMMIT;
SQL

echo "=== $(date -Iseconds) hold done ==="
