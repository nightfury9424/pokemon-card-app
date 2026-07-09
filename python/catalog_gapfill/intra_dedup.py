#!/usr/bin/env python3
"""최종 add 대상 후보끼리 동일일러스트 중복 검사 + 재판 자동제외(원판 유지) + 클러스터 검수 HTML.
중복판정: KO↔KO≥0.92 ∪ 동일 jp_ref ∪ 동일 en_ref(NO_EN 제외). ≥0.97 강함/0.92~0.97 수동.
대표선택: 하이클래스팩(VSTAR유니버스·VMAX클라이맥스·샤이니스타 등 재판/컴필) 제외, 확장팩(원판) 유지. 불명확=수동."""
import json, urllib.request, numpy as np, cv2, torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
UA={'User-Agent':'Mozilla/5.0'}
def dl(u):
    try: return cv2.imdecode(np.frombuffer(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=20).read(),np.uint8),cv2.IMREAD_COLOR)
    except Exception: return None
cards=json.load(open("/tmp/final_add.json"))
proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base"); mdl=AutoModel.from_pretrained("/Users/fury/pokemon-card-app/scanner/model/dinov2_finetuned").eval()
def emb(img):
    i=proc(images=Image.fromarray(cv2.cvtColor(img,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**i)
    v=o.last_hidden_state[:,0,:].numpy()[0]; return v/np.linalg.norm(v)
E={}
for c in cards:
    im=dl(c['ko_img'])
    if im is not None: E[c['code']]=emb(im)
# adjacency
idx={c['code']:c for c in cards}
codes=[c['code'] for c in cards if c['code'] in E]
parent={c:c for c in codes}
def find(x):
    while parent[x]!=x: parent[x]=parent[parent[x]]; x=parent[x]
    return x
def union(a,b): parent[find(a)]=find(b)
edges={}
for i in range(len(codes)):
    for j in range(i+1,len(codes)):
        a,b=codes[i],codes[j]; ca,cb=idx[a],idx[b]
        sim=float(np.dot(E[a],E[b]))
        sameJp=ca['jp_ref']==cb['jp_ref']
        sameEn=ca['en_ref']==cb['en_ref'] and ca['en_ref']!='NO_EN'
        if sim>=0.92 or sameJp or sameEn:
            union(a,b); edges[(a,b)]={'sim':round(sim,3),'sameJp':sameJp,'sameEn':sameEn}
from collections import defaultdict
clusters=defaultdict(list)
for c in codes: clusters[find(c)].append(c)
clusters={k:v for k,v in clusters.items() if len(v)>1}
def isReprint(c): return any(s in (c.get('ko_set') or '') for s in ['하이클래스팩','VSTAR 유니버스','VMAX 클라이맥스','샤이니스타','25th'])
# 대표선택
result=[]
for root,mem in clusters.items():
    cs=[idx[m] for m in mem]
    orig=[c for c in cs if not isReprint(c)]
    auto = len(orig)==1
    keep = orig[0]['code'] if auto else None
    result.append({'members':cs,'keep_rec':keep,'auto':auto,
        'pair_evidence':[{**edges[k],'a':k[0][:10],'b':k[1][:10]} for k in edges if find(k[0]) in mem]})
excluded=sum(len(r['members'])-1 for r in result)
print(f"=== intra-dedup: {len(cards)}장 중 중복클러스터 {len(result)}개, 재판 제외후보 {excluded}장 ===")
for r in result:
    print(f"\n  클러스터({len(r['members'])}){'자동' if r['auto'] else '★수동'}:")
    for c in r['members']:
        tag='유지(원판)' if c['code']==r['keep_rec'] else ('제외(재판)' if r['auto'] else '?')
        print(f"    [{tag}] {c['ko_name']}({c['rarity']}) {c['ko_set']} #{c['ko_no']} jp={c['jp_ref']} en={c['en_ref']}")
json.dump([{'members':r['members'],'keep_rec':r['keep_rec'],'auto':r['auto']} for r in result],open("/tmp/dedup_clusters.json","w"),ensure_ascii=False)
print(f"\n  최종 add 예상 = {len(cards)} - {excluded} = {len(cards)-excluded}장")
print("  → /tmp/dedup_clusters.json")
