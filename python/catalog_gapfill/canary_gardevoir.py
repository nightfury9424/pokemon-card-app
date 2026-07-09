#!/usr/bin/env python3
"""가디안 CHR canary 1장 숨김 COMMIT (is_visible=false) + SCRYDEX_JP RAW + KO_ESTIMATED 백필.
V6_BOOTSTRAP_SNAPSHOT_20260622(CHR 0.342) 런타임 오버라이드. 실제 prod write(COMMIT). 1장만."""
import sys, json, hashlib
sys.path.insert(0, '/Users/fury/pokemon-card-app/python/catalog_import')
import import_card_set as ics

PAYSHA='ffd3feb531b2aacf7d65b2fff3da15a01fb79d9b9d49c51bfd4a397e694da221'
SNAPSHA='3c8aefcf97b63da185c6f178c42182a8429ba93c1e81ca8c6aa26751eeeb014f'
assert hashlib.sha256(open('final_53_payload.json','rb').read()).hexdigest()==PAYSHA,'payload SHA 불일치'
snap=json.load(open('audit/V6_BOOTSTRAP_SNAPSHOT_20260622.json')); coef=snap['coefficients']
assert hashlib.sha256(json.dumps(coef,sort_keys=True).encode()).hexdigest()==SNAPSHA,'스냅샷 SHA 불일치'
ics.FROZEN_RTR={**dict(ics.FROZEN_RTR),**coef}
g=json.load(open('/tmp/canary_gardevoir.json'))
assert g['rarity']=='CHR' and g['name']=='가디안', 'canary 카드 아님'
print(f"canary={g['name']} {g['rarity']} {g['card_id']} jp={g['jp_scrydex_ref']} CHR계수={coef['CHR']}")
r=dict(jp_ref=g['jp_scrydex_ref'],name=g['name'],rarity='CHR',col=str(g['collection_number']),
       super_type=g['super_type'],sub_type=None,official=None,en=g['en_scrydex_ref'],
       card_id=g['card_id'],product_id=g['product_id'])
rate=ics.live_rate(); print(f"환율 rate={rate}")
cv=ics.card_values(r,r['product_id'],r['card_id'])
jpv,kov=ics.backfill_values(r['card_id'],r['jp_ref'],r['rarity'],rate)
expN=len(jpv); print(f"백필 예상: SCRYDEX_JP {len(jpv)} · KO_ESTIMATED {len(kov)} 행")
cid=ics.q(r['card_id'])
sql=["\\set ON_ERROR_STOP on","\\echo '=== BEFORE ==='",
 "SELECT count(*) before_cards FROM cards;",
 "SELECT count(*) ps_tot, COALESCE(sum(price),0) ps_sum FROM price_snapshots;",
 "BEGIN;",
 "INSERT INTO cards (card_id,product_id,official_card_code,name,collection_number,card_number,rarity_code,language,super_type,sub_type,en_scrydex_ref,jp_scrydex_ref,is_visible) VALUES "+cv+";",
 "INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,card_status,traded_at,collected_at,created_at,raw_price,raw_currency) VALUES "+",\n".join(jpv)+";",
 "INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,chart_price,card_status,traded_at,collected_at,created_at) VALUES "+",\n".join(kov)+";",
 "COMMIT;",
 "\\echo '=== AFTER (COMMIT) ==='",
 "SELECT count(*) after_cards FROM cards;",
 "SELECT count(*) ps_tot_after, COALESCE(sum(price),0) ps_sum_after FROM price_snapshots;",
 f"SELECT name,rarity_code,is_visible,jp_scrydex_ref,en_scrydex_ref,official_card_code FROM cards WHERE card_id={cid};",
 f"SELECT (SELECT count(*) FROM price_snapshots WHERE card_id={cid} AND source='SCRYDEX_JP') jp_n,"
 f"(SELECT count(*) FROM price_snapshots WHERE card_id={cid} AND source='KO_ESTIMATED') ko_n,"
 f"(SELECT count(*) FROM price_snapshots WHERE card_id={cid} AND source='KO_ESTIMATED' AND card_status<>'RAW') graded_ko;",
 f"SELECT ko.price ko_est, ko.chart_price, jp.price jp_krw, round(ko.price::numeric/NULLIF(jp.price,0),4) ratio_should_be_0342 "
 f"FROM (SELECT price,chart_price FROM price_snapshots WHERE card_id={cid} AND source='KO_ESTIMATED' ORDER BY traded_at DESC LIMIT 1) ko, "
 f"(SELECT price FROM price_snapshots WHERE card_id={cid} AND source='SCRYDEX_JP' ORDER BY traded_at DESC LIMIT 1) jp;"]
print("\n=== prod COMMIT 실행 ===")
print(ics.run_sql("\n".join(sql)))
print(f"\n★ 검증 기준: after_cards=3841 · jp_n=ko_n={expN} · graded_ko=0 · ratio≈0.342 · is_visible=f · ps_tot delta={2*expN}")
