#!/usr/bin/env python3
"""후보 KO 이미지를 prod 스캐너(3840 인덱스)에 /identify → 기존 prod 카드와 일러스트 일치하면 중복.
dup(score≥0.90) / check(0.85~0.90) / new(<0.85). 레쿠쟈처럼 v9가 놓친 중복도 잡음. write 0."""
import json, urllib.request, io
UA={'User-Agent':'Mozilla/5.0'}
def dl(u):
    try: return urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=20).read()
    except Exception: return None
def identify(b):
    bd='----d'; data=(f'--{bd}\r\nContent-Disposition: form-data; name="image"; filename="x.png"\r\nContent-Type: image/png\r\n\r\n').encode()+b+f'\r\n--{bd}--\r\n'.encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request('http://localhost:8082/identify',data=data,headers={'Content-Type':f'multipart/form-data; boundary={bd}'}),timeout=30))
        cs=(d.get('data',{}) or {}).get('candidates',[]); t=cs[0] if cs else {}
        return t.get('name'),t.get('cardId'),round(t.get('score',0),3)
    except Exception as e: return 'ERR',None,0

src=open("/Users/fury/pokemon-card-app/python/catalog_gapfill/series_gap_final_review_v9.html").read().split("const DATA=")[1].split("];")[0]+"]"
DATA=eval(src,{"false":False,"true":True,"null":None})
cand=[d for d in DATA if d['jp_ref'] and d['cls']!='UNRESOLVED' and d['cls']!='EXCLUDE_EXACT_REF']
out=[]
for i,d in enumerate(cand):
    b=dl(d['ko_img']) if d.get('ko_img') else None
    if b is None: out.append({**{k:d[k] for k in ('code','ko_name','rarity','cls','jp_ref','en_ref')},'verdict':'NO_KO_IMG','match':'','score':0}); continue
    nm,cid,sc=identify(b)
    v='dup' if sc>=0.90 else ('check' if sc>=0.85 else 'new')
    out.append({'code':d['code'],'ko_name':d['ko_name'],'rarity':d['rarity'],'cls':d['cls'],'jp_ref':d['jp_ref'],'en_ref':d.get('en_ref') or '','ko_img':d['ko_img'],'ko_no':d.get('ko_no'),'ko_set':d.get('ko_set'),'verdict':v,'match':nm,'match_cid':cid,'score':sc})
    if (i+1)%20==0: print(f"  ...{i+1}/{len(cand)}")
json.dump(out,open("/tmp/dedup_result.json","w"),ensure_ascii=False)
from collections import Counter
c=Counter(o['verdict'] for o in out)
print(f"\n=== dedup {len(out)}장: {dict(c)} ===")
print("DUP(기존 prod에 일러스트 존재→제외):")
for o in [x for x in out if x['verdict']=='dup']: print(f"  {o['ko_name']} ({o['rarity']}) → {o['match']} {o['score']}")
print("\nCHECK(0.85~0.90, 시각확인):")
for o in [x for x in out if x['verdict']=='check']: print(f"  {o['ko_name']} ({o['rarity']}) → {o['match']} {o['score']}")
print(f"\nNEW(신규=추가대상): {c['new']}장")
