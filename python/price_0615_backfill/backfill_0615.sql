-- ============================================================
-- 6/15 KO_ESTIMATED 차트구멍 백필 (DRAFT — 아직 실행 안 함)
-- ------------------------------------------------------------
-- 목적   : 6/15 벌크 sync가 4장만 써서 생긴 차트 구멍을 6/14 healthy 값으로 carry.
-- 성격   : 차트 미관용(cosmetic). 오늘밤 재폭등과 무관(오늘밤은 6/16 audit를 읽음).
-- 스코프 : 6/14 KO 보유 & rarity A/K/S 제외 = 3,455장 (검증된 dry-count).
--          제외 = A(13)+K(12)+S(258) 숨김등급 283 + 6/14무KO 17(신규3·무소스프로모14).
-- 안전   : 6/15 기존 4장은 NOT EXISTS로 건너뜀(중복 0). id 접두사 'ko_bf0615_'=롤백 용이.
-- 롤백   : DELETE FROM price_snapshots WHERE price_snapshot_id LIKE 'ko_bf0615_%';
-- ============================================================

-- [0] DRY-COUNT (실행 전 3,455 재확인)
SELECT count(*) AS would_insert
FROM price_snapshots p
JOIN cards c ON c.card_id = p.card_id
WHERE p.source = 'KO_ESTIMATED'
  AND p.traded_at >= '2026-06-14' AND p.traded_at < '2026-06-15'
  AND c.rarity_code NOT IN ('A','K','S')
  AND NOT EXISTS (
        SELECT 1 FROM price_snapshots x
        WHERE x.card_id = p.card_id AND x.source = 'KO_ESTIMATED'
          AND x.traded_at >= '2026-06-15' AND x.traded_at < '2026-06-16');

-- [1] APPLY (검토·승인 후에만 — 지금은 실행 금지)
-- INSERT INTO price_snapshots
--     (price_snapshot_id, card_id, source, price, card_status,
--      traded_at, collected_at, created_at, validation_status)
-- SELECT 'ko_bf0615_' || p.card_id, p.card_id, 'KO_ESTIMATED', p.price, p.card_status,
--        TIMESTAMP '2026-06-15 23:45:00', TIMESTAMP '2026-06-15 23:45:00', now(), 'VALID'
-- FROM price_snapshots p
-- JOIN cards c ON c.card_id = p.card_id
-- WHERE p.source = 'KO_ESTIMATED'
--   AND p.traded_at >= '2026-06-14' AND p.traded_at < '2026-06-15'
--   AND c.rarity_code NOT IN ('A','K','S')
--   AND NOT EXISTS (
--         SELECT 1 FROM price_snapshots x
--         WHERE x.card_id = p.card_id AND x.source = 'KO_ESTIMATED'
--           AND x.traded_at >= '2026-06-15' AND x.traded_at < '2026-06-16');
