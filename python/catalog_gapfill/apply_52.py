#!/usr/bin/env python3
"""52장(가디안 제외) 숨김 일괄 COMMIT + SCRYDEX_JP RAW + KO_ESTIMATED 백필.
V6_BOOTSTRAP_SNAPSHOT_20260622 런타임 오버라이드. 단일 트랜잭션 all-or-nothing(ON_ERROR_STOP).
is_visible=false. 실제 prod write. 스캐너 미변경."""
import sys, json, hashlib
sys.path.insert(0, '/Users/fury/pokemon-card-app/python/catalog_import')
import import_card_set as ics

PAYSHA='ffd3feb531b2aacf7d65b2fff3da15a01fb79d9b9d49c51bfd4a397e694da221'
SNAPSHA='3c8aefcf97b63da185c6f178c42182a8429ba93c1e81ca8c6aa26751eeeb014f'
GARD='CRD_91C3095AAD2E321043D0'
assert hashlib.sha256(open('final_53_payload.json','rb').read()).hexdigest()==PAYSHA
snap=json.load(open('audit/V6_BOOTSTRAP_SNAPSHOT_20260622.json')); coef=snap['coefficients']
assert hashlib.sha256(json.dumps(coef,sort_keys=True).encode()).hexdigest()==SNAPSHA
ics.FROZEN_RTR={**dict(ics.FROZEN_RTR),**coef}
assert ics.FROZEN_RTR['CHR']==0.342 and ics.FROZEN_RTR['CSR']==0.342 and ics.FROZEN_RTR['RR']==0.341, '스냅샷 미적용'
print(f"스냅샷 적용확인: CHR={ics.FROZEN_RTR['CHR']} RR={ics.FROZEN_RTR['RR']} UR={ics.FROZEN_RTR['UR']}")

pay=json.load(open('final_53_payload.json'))
c52=[p for p in pay if p['card_id']!=GARD]
assert len(c52)==52 and GARD not in [c['card_id'] for c in c52], '52장 아님/가디안 포함'
rate=ics.live_rate(); print(f"카드 52 · 환율 {rate} · scrydex 이력 fetch...")
rows=[dict(jp_ref=p['jp_scrydex_ref'],name=p['name'],rarity=p['rarity'].upper(),col=str(p['collection_number']),
           super_type=p['super_type'],sub_type=None,official=None,en=p['en_scrydex_ref'],
           card_id=p['card_id'],product_id=p['product_id']) for p in c52]
cv=[ics.card_values(r,r['product_id'],r['card_id']) for r in rows]
jpv,kov=[],[]; noraw=[]
for r in rows:
    a,b=ics.backfill_values(r['card_id'],r['jp_ref'],r['rarity'],rate); jpv+=a; kov+=b
    if len(a)==0: noraw.append(r['name'])
assert not noraw, f'RAW 이력 없는 카드: {noraw}'
print(f"백필: SCRYDEX_JP {len(jpv)} · KO_ESTIMATED {len(kov)} (예상 735/735)")
ids=",".join(ics.q(r['card_id']) for r in rows)
sql=["\\set ON_ERROR_STOP on","\\echo '=== BEFORE ==='","SELECT count(*) before_cards FROM cards;",
 "SELECT count(*) ps_tot, COALESCE(sum(price),0) ps_sum FROM price_snapshots;","BEGIN;",
 "INSERT INTO cards (card_id,product_id,official_card_code,name,collection_number,card_number,rarity_code,language,super_type,sub_type,en_scrydex_ref,jp_scrydex_ref,is_visible) VALUES",",\n".join(cv)+";",
 "INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,card_status,traded_at,collected_at,created_at,raw_price,raw_currency) VALUES",",\n".join(jpv)+";",
 "INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,chart_price,card_status,traded_at,collected_at,created_at) VALUES",",\n".join(kov)+";",
 "COMMIT;","\\echo '=== AFTER (COMMIT) ==='","SELECT count(*) after_cards FROM cards;",
 "SELECT count(*) ps_tot_after, COALESCE(sum(price),0) ps_sum_after FROM price_snapshots;",
 f"SELECT count(*) new_cards, count(*) FILTER(WHERE is_visible) visible_should_be_0 FROM cards WHERE card_id IN ({ids});",
 f"SELECT super_type,count(*) FROM cards WHERE card_id IN ({ids}) GROUP BY super_type ORDER BY super_type;",
 f"SELECT count(*) graded_as_raw_KO FROM price_snapshots WHERE card_id IN ({ids}) AND source='KO_ESTIMATED' AND card_status<>'RAW';",
 f"SELECT (SELECT count(*) FROM price_snapshots WHERE source='SCRYDEX_JP' AND card_id IN ({ids})) jp_rows,(SELECT count(*) FROM price_snapshots WHERE source='KO_ESTIMATED' AND card_id IN ({ids})) ko_rows;",
 "\\echo '--- 레어도별 KO/JP 비율(=스냅샷 계수여야) ---'",
 f"SELECT c.rarity_code, count(*) n, round(avg(ko.price::numeric/NULLIF(jp.price,0)),4) avg_ratio "
 f"FROM cards c JOIN LATERAL (SELECT price FROM price_snapshots WHERE card_id=c.card_id AND source='KO_ESTIMATED' ORDER BY traded_at DESC LIMIT 1) ko ON true "
 f"JOIN LATERAL (SELECT price FROM price_snapshots WHERE card_id=c.card_id AND source='SCRYDEX_JP' ORDER BY traded_at DESC LIMIT 1) jp ON true "
 f"WHERE c.card_id IN ({ids}) GROUP BY c.rarity_code ORDER BY c.rarity_code;"]
print("\n=== prod COMMIT 실행 (52장 숨김) ===")
print(ics.run_sql("\n".join(sql)))
print(f"\n★ 기준: after=3893 · new=52 · visible=0(숨김) · graded=0 · jp_rows=ko_rows={len(jpv)} · 레어도비율=스냅샷")
