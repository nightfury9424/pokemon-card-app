-- ============================================================================
-- price_health_report.sql  —  KO 시세 파이프라인 오작동 진단기 (READ-ONLY)
-- 실행: ssh -i <key> ubuntu@52.78.3.120 \
--   "docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db -A -F'|'" \
--   < scripts/price_health_report.sql
-- 목적: 특정 카드 가격 보정이 아니라, 시세 시스템이 어디서 오작동하는지 탐지.
-- prod WRITE 절대 없음 (SELECT only). 매 변경 전/후 실행해 before/after 비교.
--
-- 오작동 판정 규칙 (해석 가이드):
--   1. audit(ko_estimation_audit.ko_price)는 truth 아님 = 23:45 stage-2 모델값(overlay 전).
--   2. audit >= 2x live = '복구 대상' 아님 = LANDMINE(복구하면 인플레). live가 overlay 교정값.
--   3. selected_source='EN' 인데 JP raw 존재 = spread가드 JP→EN flip = JP-first 의도 위반.
--   4. DAANGN obs 있는 카드는 계수/v6/sanity가 덮으면 안 됨(실관측 우선).
--   5. MANUAL_ANCHOR / card-scope coef 는 rarity 계수보다 우선.
--   6. sanity_fire(오늘밤 sanity_cap 발동) 가 임계↑ 면 배치 abort 후보.
--   7. visible rarity 중 audit>=2x live 비율 50%↑ = 계수 과대 후보(현재 AR/CHR).
--   8. price_summaries(복수)=실거래 집계, 현재가 경로 아님. 현재가=getCardPriceSummary(@Cacheable 30m TTL).
--
-- MANUAL_ANCHOR/FLOOR 18 card_id 는 v6_apply.py 와 동기화. cap_table 은 sanity_cap_extreme_daily.sh 와 동기화.
-- ============================================================================

\echo '=== [1] OVERALL ==='
WITH ko AS(SELECT DISTINCT ON(card_id) card_id,price live FROM price_snapshots WHERE source='KO_ESTIMATED' ORDER BY card_id,traded_at DESC),
 au AS(SELECT DISTINCT ON(card_id) card_id,ko_price audit,selected_source ssrc FROM ko_estimation_audit ORDER BY card_id,estimated_date DESC),
 jp AS(SELECT DISTINCT ON(card_id) card_id,price jp_krw FROM price_snapshots WHERE source='SCRYDEX_JP' AND card_status='RAW' AND raw_currency='USD' AND raw_price BETWEEN 0.05 AND 3000 ORDER BY card_id,traded_at DESC),
 dg AS(SELECT card_id,count(*) dg_n FROM price_snapshots WHERE source='DAANGN' AND validation_status='VALID' AND traded_at>=CURRENT_DATE-180 GROUP BY card_id),
 cs AS(SELECT DISTINCT card_id FROM ko_price_coefficients WHERE active AND scope='CARD'),
 ma AS(SELECT unnest(ARRAY['CRD_5094F85922274E7CAC3C','CRD_F95322AF0A1243D99F83','CRD_25A858D01145493BB66AF82B8EA32B7C','CRD_A6F7502948814BF9A22C','CRD_B8B69E5A34C042F2928346295A367A70','CRD_54079F1439374F52BCF7','CRD_95962D36A0B54D96A10A','CRD_B8B3074785EC350DEB26','CRD_7AD3E7B95A594FFEABE6','CRD_DF3A72B78E8141B1A0D2BED89B3B20EE','CRD_853F91A8D5AF441492F4','CRD_2E403B756FE641CB89FF32CEB4BDDB4E','CRD_32C64F60484E4801A991','CRD_46627F2A3E6F48A9BE2F','CRD_BC23459C3A854031B8A0','CRD_7633E4DC01B743F4A4BC','CRD_4B0D00B3E615450ABC4E','CRD_A848A7E12690411197B4']) card_id)
SELECT count(*) total, count(*) FILTER(WHERE c.is_visible) visible,
  count(*) FILTER(WHERE au.audit>ko.live*2) audit_ge2x_live_LANDMINE,
  count(*) FILTER(WHERE ko.live>au.audit*2 AND au.audit>0) live_ge2x_audit_ANOMALY,
  count(dg.card_id) daangn_protect, count(cs.card_id) cardscope, count(ma.card_id) manual_anchor,
  count(*) FILTER(WHERE au.ssrc='EN' AND jp.card_id IS NOT NULL) en_flip_jp_exists
FROM cards c JOIN ko ON ko.card_id=c.card_id LEFT JOIN au ON au.card_id=c.card_id LEFT JOIN jp ON jp.card_id=c.card_id
 LEFT JOIN dg ON dg.card_id=c.card_id LEFT JOIN cs ON cs.card_id=c.card_id LEFT JOIN ma ON ma.card_id=c.card_id
WHERE c.language='KO' AND c.is_promo_exclusive=false;

\echo '=== [2] PER-RARITY (status: HIDDEN / SUSPECT_COEF / OK) ==='
WITH ko AS(SELECT DISTINCT ON(card_id) card_id,price live FROM price_snapshots WHERE source='KO_ESTIMATED' ORDER BY card_id,traded_at DESC),
 au AS(SELECT DISTINCT ON(card_id) card_id,ko_price audit FROM ko_estimation_audit ORDER BY card_id,estimated_date DESC),
 jp AS(SELECT DISTINCT ON(card_id) card_id,price jp_krw FROM price_snapshots WHERE source='SCRYDEX_JP' AND card_status='RAW' AND raw_currency='USD' AND raw_price BETWEEN 0.05 AND 3000 ORDER BY card_id,traded_at DESC),
 en AS(SELECT DISTINCT ON(card_id) card_id,price en_krw FROM price_snapshots WHERE source='SCRYDEX_EN' AND card_status='RAW' AND raw_currency='USD' AND raw_price BETWEEN 0.05 AND 3000 ORDER BY card_id,traded_at DESC),
 dgp AS(SELECT DISTINCT ON(card_id) card_id,price dg_krw FROM price_snapshots WHERE source='DAANGN' AND validation_status='VALID' AND traded_at>=CURRENT_DATE-180 ORDER BY card_id,traded_at DESC),
 dg AS(SELECT card_id,count(*) dg_n FROM price_snapshots WHERE source='DAANGN' AND validation_status='VALID' AND traded_at>=CURRENT_DATE-180 GROUP BY card_id),
 cs AS(SELECT DISTINCT card_id FROM ko_price_coefficients WHERE active AND scope='CARD'),
 capt AS(SELECT * FROM(VALUES('HR',0.272,0.258),('AR',0.362,0.114),('PR',0.723,0.980),('MA',0.420,0.290),('SAR',0.422,0.362),('BWR',0.388,0.208),('SR',0.805,0.964),('RR',0.846,0.401),('MUR',0.468,0.447),('UR',1.192,0.728)) AS t(rar,jpp,enp))
SELECT c.rarity_code rar, count(*) n, count(*) FILTER(WHERE c.is_visible) vis,
  percentile_cont(0.5) WITHIN GROUP(ORDER BY ko.live)::int live_med,
  count(*) FILTER(WHERE au.audit>ko.live*2) audit2x,
  round(percentile_cont(0.5) WITHIN GROUP(ORDER BY dgp.dg_krw::numeric/NULLIF(jp.jp_krw,0))::numeric,3) ko_jp_obs,
  count(dg.card_id) daangn, count(cs.card_id) cscope,
  count(*) FILTER(WHERE LEAST(NULLIF((jp.jp_krw*capt.jpp)::int,0),NULLIF((en.en_krw*capt.enp)::int,0))>0 AND ko.live>LEAST(NULLIF((jp.jp_krw*capt.jpp)::int,0),NULLIF((en.en_krw*capt.enp)::int,0))*3) AS sanity_fire,
  CASE WHEN count(*) FILTER(WHERE c.is_visible)=0 THEN 'HIDDEN'
       WHEN count(*) FILTER(WHERE au.audit>ko.live*2)::float/NULLIF(count(*),0) > 0.4 THEN 'SUSPECT_COEF'
       ELSE 'OK' END status
FROM cards c JOIN ko ON ko.card_id=c.card_id LEFT JOIN au ON au.card_id=c.card_id LEFT JOIN jp ON jp.card_id=c.card_id
 LEFT JOIN en ON en.card_id=c.card_id LEFT JOIN dgp ON dgp.card_id=c.card_id LEFT JOIN dg ON dg.card_id=c.card_id LEFT JOIN cs ON cs.card_id=c.card_id LEFT JOIN capt ON capt.rar=c.rarity_code
WHERE c.language='KO' AND c.is_promo_exclusive=false
GROUP BY c.rarity_code ORDER BY n DESC;

\echo '=== [3] LANDMINE TOP20 (audit >= 2x live, visible) — 복구 절대 금지 ==='
WITH ko AS(SELECT DISTINCT ON(card_id) card_id,price live FROM price_snapshots WHERE source='KO_ESTIMATED' ORDER BY card_id,traded_at DESC),
 au AS(SELECT DISTINCT ON(card_id) card_id,ko_price audit,selected_source ssrc FROM ko_estimation_audit ORDER BY card_id,estimated_date DESC)
SELECT left(c.name,16) nm, c.rarity_code rar, c.collection_number col, ko.live, au.audit, au.ssrc, round(au.audit::numeric/NULLIF(ko.live,0),1) x
FROM cards c JOIN ko ON ko.card_id=c.card_id JOIN au ON au.card_id=c.card_id
WHERE c.language='KO' AND c.is_promo_exclusive=false AND c.is_visible AND au.audit>ko.live*2
ORDER BY au.audit-ko.live DESC LIMIT 20;

\echo '=== [4] SPREAD-FLIP TOP20 (selected_source=EN but JP exists, visible) ==='
WITH ko AS(SELECT DISTINCT ON(card_id) card_id,price live FROM price_snapshots WHERE source='KO_ESTIMATED' ORDER BY card_id,traded_at DESC),
 au AS(SELECT DISTINCT ON(card_id) card_id,ko_price audit,selected_source ssrc FROM ko_estimation_audit ORDER BY card_id,estimated_date DESC),
 jp AS(SELECT DISTINCT ON(card_id) card_id,price jp_krw FROM price_snapshots WHERE source='SCRYDEX_JP' AND card_status='RAW' AND raw_currency='USD' AND raw_price BETWEEN 0.05 AND 3000 ORDER BY card_id,traded_at DESC),
 en AS(SELECT DISTINCT ON(card_id) card_id,price en_krw FROM price_snapshots WHERE source='SCRYDEX_EN' AND card_status='RAW' AND raw_currency='USD' AND raw_price BETWEEN 0.05 AND 3000 ORDER BY card_id,traded_at DESC)
SELECT left(c.name,16) nm, c.rarity_code rar, ko.live, au.audit, jp.jp_krw, en.en_krw, round(en.en_krw::numeric/NULLIF(jp.jp_krw,0),1) en_jp_x
FROM cards c JOIN ko ON ko.card_id=c.card_id JOIN au ON au.card_id=c.card_id JOIN jp ON jp.card_id=c.card_id LEFT JOIN en ON en.card_id=c.card_id
WHERE c.language='KO' AND c.is_promo_exclusive=false AND c.is_visible AND au.ssrc='EN'
ORDER BY au.audit DESC LIMIT 20;

\echo '=== [5] CARD-SCOPE STALE (card-scope JP coef vs rarity, 높음=stale 의심) ==='
SELECT left(c.name,16) nm, c.rarity_code rar, c.collection_number col, k.coef_type, k.coef
FROM ko_price_coefficients k JOIN cards c ON c.card_id=k.card_id
WHERE k.active AND k.scope='CARD' AND c.language='KO'
ORDER BY c.rarity_code, c.name, k.coef_type;

\echo '=== [6] SANITY_FIRE TONIGHT (오늘밤 sanity_cap 발동 예정) ==='
WITH ko AS(SELECT DISTINCT ON(card_id) card_id,price live FROM price_snapshots WHERE source='KO_ESTIMATED' ORDER BY card_id,traded_at DESC),
 jp AS(SELECT DISTINCT ON(card_id) card_id,price jp_krw FROM price_snapshots WHERE source='SCRYDEX_JP' AND card_status='RAW' AND raw_currency='USD' AND raw_price BETWEEN 0.05 AND 3000 ORDER BY card_id,traded_at DESC),
 en AS(SELECT DISTINCT ON(card_id) card_id,price en_krw FROM price_snapshots WHERE source='SCRYDEX_EN' AND card_status='RAW' AND raw_currency='USD' AND raw_price BETWEEN 0.05 AND 3000 ORDER BY card_id,traded_at DESC),
 dg AS(SELECT card_id,count(*) dg_n FROM price_snapshots WHERE source='DAANGN' AND validation_status='VALID' AND traded_at>=CURRENT_DATE-180 GROUP BY card_id),
 capt AS(SELECT * FROM(VALUES('HR',0.272,0.258),('AR',0.362,0.114),('PR',0.723,0.980),('MA',0.420,0.290),('SAR',0.422,0.362),('BWR',0.388,0.208),('SR',0.805,0.964),('RR',0.846,0.401),('MUR',0.468,0.447),('UR',1.192,0.728)) AS t(rar,jpp,enp))
SELECT left(c.name,16) nm, c.rarity_code rar, ko.live,
  LEAST(NULLIF((jp.jp_krw*capt.jpp)::int,0),NULLIF((en.en_krw*capt.enp)::int,0)) cap_value, COALESCE(dg.dg_n,0) dg_n
FROM cards c JOIN ko ON ko.card_id=c.card_id LEFT JOIN jp ON jp.card_id=c.card_id LEFT JOIN en ON en.card_id=c.card_id
 LEFT JOIN dg ON dg.card_id=c.card_id JOIN capt ON capt.rar=c.rarity_code
WHERE c.language='KO' AND c.is_promo_exclusive=false
  AND LEAST(NULLIF((jp.jp_krw*capt.jpp)::int,0),NULLIF((en.en_krw*capt.enp)::int,0)) > 0
  AND ko.live > LEAST(NULLIF((jp.jp_krw*capt.jpp)::int,0),NULLIF((en.en_krw*capt.enp)::int,0))*3
ORDER BY ko.live DESC;

\echo '=== [7] LIVE >= 2x AUDIT (overlay가 모델보다 올린 이상 케이스) ==='
WITH ko AS(SELECT DISTINCT ON(card_id) card_id,price live FROM price_snapshots WHERE source='KO_ESTIMATED' ORDER BY card_id,traded_at DESC),
 au AS(SELECT DISTINCT ON(card_id) card_id,ko_price audit FROM ko_estimation_audit ORDER BY card_id,estimated_date DESC)
SELECT left(c.name,16) nm, c.rarity_code rar, ko.live, au.audit
FROM cards c JOIN ko ON ko.card_id=c.card_id JOIN au ON au.card_id=c.card_id
WHERE c.language='KO' AND c.is_promo_exclusive=false AND ko.live>au.audit*2 AND au.audit>0
ORDER BY ko.live-au.audit DESC LIMIT 20;
