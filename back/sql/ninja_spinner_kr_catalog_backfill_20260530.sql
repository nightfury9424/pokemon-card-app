-- ============================================================================
-- 닌자스피너 (m4_ja) KO 카탈로그 보강 — 2026-05-30
-- ============================================================================
--
-- 배경:
--   한국 출시 직후 pokemoncard.co.kr 등록 지연으로 KO master 9장 (RR 8 + MUR 1)
--   만 존재. 일본 m4_ja 정상 set 38~40장 대비 27장 누락 (AR 12 + SR 18 + SAR 6
--   + MUR 1 = 37 중 11 = 30% 만 수입).
--   → 사용자 검증 (KREAM, ChitoroShop, 포켓몬 도감 한국 공식명) 후 27장 보강.
--
-- 정책 준수:
--   - 도구류 제외: ITEM 3장 (104/105/106), POKEMON_TOOL 1장 (107),
--                  STADIUM 2장 (112 서핑비치, 113 프리즘타워 LR)
--   - 한국명 미확정 3장 보류: 095 Watchog, 109 Philippe, 111 Emma
--                              (외부 source 추가 검증 후 별 cycle)
--   - 가격 backfill 미포함: price_snapshots 는 SCRYDEX cron 자동 흐름 (또는 별 backfill cycle)
--
-- 방어 패턴:
--   - jp_scrydex_ref 기준 NOT EXISTS — prod 이미 INSERT 끝났으므로 재실행 시 0건
--   - card_id 는 random UUID 20-hex (기존 SAR 6장과 동일 패턴)
--
-- 검증 (실행 후 분포 — 기대값):
--   MUR  1, SAR  6, SR  10, AR  11, RR  8 = 총 36장
--   095/109/111 추가 INSERT 시 → 총 39장 (인페르노X 34/니힐제로 38 동급)
--
-- 참고:
--   - 기존 prod 적용: 2026-05-30 (SAR 6장 1차 + AR 11 + SR 10 2차 = 21장 직접 INSERT 후 본 파일로 영구화)
--   - product_id: PRD_156BB71C4F5A41C39521
--   - jp_scrydex_ref 패턴: m4_ja-{collection_number_int} (앞자리 0 없음)
-- ============================================================================

BEGIN;

INSERT INTO cards (
  card_id, product_id, collection_number,
  rarity_code, super_type, sub_type, name, language,
  jp_scrydex_ref, en_scrydex_ref,
  is_promo_exclusive, popularity_score, name_locked, is_visible
)
SELECT
  'CRD_' || UPPER(substring(REPLACE(gen_random_uuid()::text, '-', ''), 1, 20)),
  t.pid, t.col, t.rarity, t.super, t.sub, t.name, 'KO',
  t.jpref, 'NO_EN',
  false, 0, false, true
FROM (VALUES
  -- SAR 6장 (col 114-119) — 1차 INSERT (2026-05-30)
  ('PRD_156BB71C4F5A41C39521', '114/083', 'SAR', 'POKEMON', 'STAGE2',    '메가개굴닌자 ex', 'm4_ja-114'),
  ('PRD_156BB71C4F5A41C39521', '115/083', 'SAR', 'POKEMON', 'BASIC',     '메가플라엣테 ex', 'm4_ja-115'),
  ('PRD_156BB71C4F5A41C39521', '116/083', 'SAR', 'POKEMON', 'STAGE1',    '메가드래캄 ex',   'm4_ja-116'),
  ('PRD_156BB71C4F5A41C39521', '117/083', 'SAR', 'POKEMON', 'EX',        '치라치노 ex',     'm4_ja-117'),
  ('PRD_156BB71C4F5A41C39521', '118/083', 'SAR', 'TRAINER', 'SUPPORTER', 'AZ의 평온',       'm4_ja-118'),
  ('PRD_156BB71C4F5A41C39521', '119/083', 'SAR', 'TRAINER', 'SUPPORTER', '보미카의 연주',   'm4_ja-119'),

  -- AR 11장 (col 084-094, 095 Watchog 보류) — 2차 INSERT (2026-05-30)
  ('PRD_156BB71C4F5A41C39521', '084/083', 'AR',  'POKEMON', 'BASIC',  '도치마론',   'm4_ja-84'),
  ('PRD_156BB71C4F5A41C39521', '085/083', 'AR',  'POKEMON', 'BASIC',  '푸호꼬',     'm4_ja-85'),
  ('PRD_156BB71C4F5A41C39521', '086/083', 'AR',  'POKEMON', 'BASIC',  '개구마르',   'm4_ja-86'),
  ('PRD_156BB71C4F5A41C39521', '087/083', 'AR',  'POKEMON', 'STAGE1', '개굴반장',   'm4_ja-87'),
  ('PRD_156BB71C4F5A41C39521', '088/083', 'AR',  'POKEMON', 'STAGE2', '전룡',       'm4_ja-88'),
  ('PRD_156BB71C4F5A41C39521', '089/083', 'AR',  'POKEMON', 'BASIC',  '제르네아스', 'm4_ja-89'),
  ('PRD_156BB71C4F5A41C39521', '090/083', 'AR',  'POKEMON', 'STAGE1', '클레이돌',   'm4_ja-90'),
  ('PRD_156BB71C4F5A41C39521', '091/083', 'AR',  'POKEMON', 'STAGE2', '크로뱃',     'm4_ja-91'),
  ('PRD_156BB71C4F5A41C39521', '092/083', 'AR',  'POKEMON', 'STAGE1', '메탕',       'm4_ja-92'),
  ('PRD_156BB71C4F5A41C39521', '093/083', 'AR',  'POKEMON', 'STAGE1', '미끄네일',   'm4_ja-93'),
  ('PRD_156BB71C4F5A41C39521', '094/083', 'AR',  'POKEMON', 'BASIC',  '켄타로스',   'm4_ja-94'),

  -- SR 10장 (col 096-103 + 108 + 110) — 2차 INSERT (2026-05-30)
  -- 제외: 104-107 ITEM/TOOL (도구 정책), 112-113 STADIUM (프리즘타워 LR 포함), 109/111 보류
  ('PRD_156BB71C4F5A41C39521', '096/083', 'SR',  'POKEMON', 'EX',        '독침붕 ex',       'm4_ja-96'),
  ('PRD_156BB71C4F5A41C39521', '097/083', 'SR',  'POKEMON', 'STAGE1',    '메가화염레오 ex', 'm4_ja-97'),
  ('PRD_156BB71C4F5A41C39521', '098/083', 'SR',  'POKEMON', 'STAGE2',    '메가개굴닌자 ex', 'm4_ja-98'),
  ('PRD_156BB71C4F5A41C39521', '099/083', 'SR',  'POKEMON', 'BASIC',     '메가플라엣테 ex', 'm4_ja-99'),
  ('PRD_156BB71C4F5A41C39521', '100/083', 'SR',  'POKEMON', 'EX',        '펌킨인 ex',       'm4_ja-100'),
  ('PRD_156BB71C4F5A41C39521', '101/083', 'SR',  'POKEMON', 'EX',        '코바르온 ex',     'm4_ja-101'),
  ('PRD_156BB71C4F5A41C39521', '102/083', 'SR',  'POKEMON', 'STAGE1',    '메가드래캄 ex',   'm4_ja-102'),
  ('PRD_156BB71C4F5A41C39521', '103/083', 'SR',  'POKEMON', 'EX',        '치라치노 ex',     'm4_ja-103'),
  ('PRD_156BB71C4F5A41C39521', '108/083', 'SR',  'TRAINER', 'SUPPORTER', 'AZ의 평온',       'm4_ja-108'),
  ('PRD_156BB71C4F5A41C39521', '110/083', 'SR',  'TRAINER', 'SUPPORTER', '보미카의 연주',   'm4_ja-110')
) AS t(pid, col, rarity, super, sub, name, jpref)
WHERE NOT EXISTS (
  SELECT 1 FROM cards c
  WHERE c.jp_scrydex_ref = t.jpref
    AND c.language = 'KO'
);

-- 검증: 기대값 MUR 1 / SAR 6 / SR 10 / AR 11 / RR 8 = 36장
SELECT
  '닌자스피너 KO 분포 (검증)' AS info,
  rarity_code, COUNT(*) AS cnt
FROM cards
WHERE product_id = 'PRD_156BB71C4F5A41C39521'
  AND language = 'KO'
  AND is_visible = TRUE
GROUP BY rarity_code
ORDER BY CASE rarity_code
  WHEN 'MUR' THEN 1 WHEN 'SAR' THEN 2 WHEN 'SR' THEN 3
  WHEN 'AR'  THEN 4 WHEN 'RR'  THEN 5 ELSE 99
END;

COMMIT;

-- ============================================================================
-- 후속 작업 (별 cycle):
--   1. 095 Watchog / 109 Philippe / 111 Emma 한국명 확정 후 추가 INSERT (3장)
--   2. SCRYDEX 과거 가격 backfill (한국 출시일 cutoff 적용)
--   3. KO_ESTIMATED 산식 적용 backfill (freeze 산식 그대로)
--   4. hits_priced.md 재생성 + hits_picks_v3 자동 추출
--   5. product_hits_overrides 적용 → 도감 화면 final
-- ============================================================================
