#!/usr/bin/env python3
"""53장 통합 DB dry-run (v6 부트스트랩 스냅샷 적용). BEGIN→INSERT cards+SCRYDEX_JP RAW+KO_ESTIMATED→검증→ROLLBACK.
스냅샷=V6_BOOTSTRAP_SNAPSHOT_20260622(파일 로드+SHA검증+런타임 오버라이드, import_card_set 파일 불변).
카드별 3-way 비교(옛 FROZEN_RTR / v6스냅샷 / 당근). 실반영 0. prod write 0."""
import sys, json, hashlib, random
sys.path.insert(0, '/Users/fury/pokemon-card-app/python/catalog_import')
import import_card_set as ics

PAYSHA='ffd3feb531b2aacf7d65b2fff3da15a01fb79d9b9d49c51bfd4a397e694da221'
assert hashlib.sha256(open('final_53_payload.json','rb').read()).hexdigest()==PAYSHA,'payload SHA 불일치'
snap=json.load(open('audit/V6_BOOTSTRAP_SNAPSHOT_20260622.json')); coef=snap['coefficients']
assert hashlib.sha256(json.dumps(coef,sort_keys=True).encode()).hexdigest()==snap['coefficients_sha256'],'스냅샷 SHA 불일치'
OLD=dict(ics.FROZEN_RTR)
ics.FROZEN_RTR={**OLD,**coef}   # 런타임 오버라이드 (파일 불변)
print(f"감사: {snap['snapshot_id']} 계수SHA={snap['coefficients_sha256'][:16]} 적용카드={len(snap['applies_card_ids'])}")
# 당근 레어도 ratio (확인결과, 비교용·미적용)
DA={'RR':(0.467,'noisy'),'AR':(0.212,'wide'),'SR':(0.342,'wide'),'SAR':(0.283,'good'),'UR':(0.536,'thin'),'RRR':(0.642,'thin'),'SSR':(0.630,'thin'),'HR':(0.181,'weak'),'CHR':(0.370,'n1'),'CSR':(0.773,'n3')}

pay=json.load(open('final_53_payload.json')); rate=ics.live_rate()
print(f"환율 rate={rate}\n카드 53 · scrydex 가격이력 fetch...")
rows=[dict(jp_ref=p['jp_scrydex_ref'],name=p['name'],rarity=p['rarity'].upper(),col=str(p['collection_number']),
           super_type=p['super_type'],sub_type=None,official=None,en=p['en_scrydex_ref'],
           card_id=p['card_id'],product_id=p['product_id']) for p in pay]
cv=[ics.card_values(r,r['product_id'],r['card_id']) for r in rows]
jpv,kov=[],[]; cmp=[]
for r in rows:
    a,b=ics.backfill_values(r['card_id'],r['jp_ref'],r['rarity'],rate); jpv+=a; kov+=b
    h=ics.scrydex_history(r['jp_ref'])
    jpk=round(max(h,key=lambda x:x[0])[1]*rate) if h else 0
    rar=r['rarity']
    old=round(jpk*OLD[rar]) if rar in OLD else None
    sn=round(jpk*coef[rar]); da=round(jpk*DA[rar][0]) if rar in DA else None
    cmp.append((r['name'],rar,len(a),jpk,old,sn,da,DA.get(rar,('','-'))[1]))
ids=",".join(ics.q(r['card_id']) for r in rows)
noraw=[c for c in cmp if c[2]==0]
print(f"\n=== 카드별 3-way 비교 (JP_KRW × 계수) ===")
print(f"  {'카드':20}{'rar':5}{'jp이력':6}{'JP_KRW':9}{'옛FROZEN':10}{'★v6스냅샷':10}{'당근(미적용)':12}")
for nm,rar,n,jpk,old,sn,da,daf in cmp:
    print(f"  {nm[:18]:20}{rar:5}{n:<6}{jpk:<9}{(old if old is not None else 'N/A'):<10}{sn:<10}{(str(da)+'/'+daf) if da is not None else 'N/A':<12}")
if noraw: print(f"  ⚠️ JP raw 이력 0 (가격 백필 불가): {[c[0] for c in noraw]}")

sql=["\\set ON_ERROR_STOP on","\\echo '=== BEFORE ==='","SELECT count(*) before_cards FROM cards;",
 "SELECT count(*) ps_tot, COALESCE(sum(price),0) ps_sum FROM price_snapshots;","BEGIN;",
 "INSERT INTO cards (card_id,product_id,official_card_code,name,collection_number,card_number,rarity_code,language,super_type,sub_type,en_scrydex_ref,jp_scrydex_ref,is_visible) VALUES",",\n".join(cv)+";"]
if jpv: sql+=["INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,card_status,traded_at,collected_at,created_at,raw_price,raw_currency) VALUES",",\n".join(jpv)+";"]
if kov: sql+=["INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,chart_price,card_status,traded_at,collected_at,created_at) VALUES",",\n".join(kov)+";"]
sql+=["\\echo '=== IN-TX 검증 ==='","SELECT count(*) intx_cards FROM cards;",
 f"SELECT count(*) new_cards FROM cards WHERE card_id IN ({ids});",
 f"SELECT super_type,count(*) FROM cards WHERE card_id IN ({ids}) GROUP BY super_type ORDER BY super_type;",
 f"SELECT count(*) graded_as_raw_KO FROM price_snapshots WHERE card_id IN ({ids}) AND source='KO_ESTIMATED' AND card_status<>'RAW';",
 f"SELECT (SELECT count(*) FROM price_snapshots p WHERE p.source='SCRYDEX_JP' AND p.card_id IN ({ids})) jp_rows,(SELECT count(*) FROM price_snapshots p WHERE p.source='KO_ESTIMATED' AND p.card_id IN ({ids})) ko_rows;",
 "ROLLBACK;","\\echo '=== AFTER ==='","SELECT count(*) after_cards FROM cards;",
 "SELECT count(*) ps_tot_after, COALESCE(sum(price),0) ps_sum_after FROM price_snapshots;"]
print("\n=== prod dry-run (BEGIN→INSERT→검증→ROLLBACK) ===")
print(ics.run_sql("\n".join(sql)))
