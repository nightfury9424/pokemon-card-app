-- 백필 (CARD_ID 치환 후 실행). price_snapshot_id=BFILL_ 프리픽스(롤백용)
-- SCRYDEX_JP
INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,card_status,traded_at,collected_at,created_at,raw_price,raw_currency)
SELECT 'BFILL_'||:cid||'_JP_'||d.date, :cid_v,'SCRYDEX_JP',d.jp_krw,'RAW',d.date::timestamp,d.date::timestamp,now(),d.usd,'USD'
FROM (VALUES {JP_VALUES}) AS d(date,jp_krw,usd)
WHERE NOT EXISTS (SELECT 1 FROM price_snapshots p WHERE p.card_id=:cid_v AND p.source='SCRYDEX_JP' AND p.traded_at::date=d.date::date);
-- KO_ESTIMATED (+chart_price 컬럼)
INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,chart_price,card_status,traded_at,collected_at,created_at)
SELECT 'BFILL_'||:cid||'_KO_'||d.date, :cid_v,'KO_ESTIMATED',d.ko,d.cp,'RAW',d.date::timestamp,d.date::timestamp,now()
FROM (VALUES {KO_VALUES}) AS d(date,ko,cp)
WHERE NOT EXISTS (SELECT 1 FROM price_snapshots p WHERE p.card_id=:cid_v AND p.source='KO_ESTIMATED' AND p.traded_at::date=d.date::date);