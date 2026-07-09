#!/usr/bin/env python3
"""EN 미매칭 재매칭: pokemontcg.io 이름검색 → 각 후보 이미지 DINOv2로 JP 일러스트와 매칭 → best.
원 매처(en_match2)가 JP셋의 EN-대응셋 1개만 봐서 TG/갤러리 서브셋(swsh10tg 등) 놓친 것 보완.
scrydex ref = {set.id}-{number}. 검증: scrydex 이미지 200. write 0 (검토용 CSV만)."""
import urllib.request, urllib.parse, json, numpy as np, cv2, torch, csv
from PIL import Image
from transformers import AutoImageProcessor, AutoModel

# jp_ref → (EN name, subtype filter|None)
NAMEMAP = {
 'swsh12a_ja-229':('samurott','V'), 'sv2p_ja-94':('lurantis','ex'),
 'swsh8b_ja-120':('rayquaza','VMAX'), 'swsh8b_ja-123':('duraludon','VMAX'),
 'swsh8b_ja-196':('gardevoir',None), 'swsh8b_ja-198':('dusknoir',None),
 'swsh8b_ja-201':('alcremie',None), 'swsh8b_ja-237':('zapdos','V'),
 'swsh8b_ja-251':('zamazenta','V'), 'swsh8b_ja-253':('duraludon','VMAX'),
 'swsh10a_ja-88':('tornadus','V'), 'swsh11a_ja-73':('indeedee',None),
 'swsh8a_ja-22':('pikachu','VMAX'), 'swsh8a_ja-24':('pikachu','VMAX'),
 'swsh4a_ja-323':('ditto','V'),
}
UA = {'User-Agent':'Mozilla/5.0'}
def jget(u): return json.load(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=30))
def dl(u):
    try:
        d=urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=25).read()
        return cv2.imdecode(np.frombuffer(d,np.uint8),cv2.IMREAD_COLOR)
    except Exception: return None

proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base")
mdl=AutoModel.from_pretrained("/Users/fury/pokemon-card-app/scanner/model/dinov2_finetuned").eval()
def emb(img):
    i=proc(images=Image.fromarray(cv2.cvtColor(img,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**i)
    v=o.last_hidden_state[:,0,:].numpy()[0]; return v/np.linalg.norm(v)

rows=[]
for jp,(name,sub) in NAMEMAP.items():
    jpimg=dl(f"https://images.scrydex.com/pokemon/{jp}/medium")
    if jpimg is None: rows.append([jp,name,'JP_IMG_FAIL','',0,'']); print(jp,'JP_IMG_FAIL'); continue
    je=emb(jpimg)
    q=f"name:{name}"+(f" subtypes:{sub}" if sub else "")
    try: r=jget(f"https://api.pokemontcg.io/v2/cards?q={urllib.parse.quote(q)}&pageSize=80")
    except Exception as e: rows.append([jp,name,'API_FAIL','',0,str(e)[:30]]); print(jp,'API_FAIL'); continue
    cands=r.get('data',[]); best=None; n=0
    for c in cands:
        img=dl(c['images']['large'])
        if img is None: continue
        cos=float(np.dot(emb(img),je)); n+=1
        if best is None or cos>best[2]: best=(c['set']['id'],c.get('number'),cos)
    if best and best[2]>=0.85:
        sref=f"{best[0]}-{best[1]}"; sc=dl(f"https://images.scrydex.com/pokemon/{sref}/medium")
        rows.append([jp,name,sref,round(best[2],3),n,'scrydex_O' if sc is not None else 'scrydex_X'])
        print(f"  {jp} {name} → {sref} cos={best[2]:.3f} (후보{n}) {'scrydexO' if sc is not None else 'scrydexX'}")
    else:
        rows.append([jp,name,'NO_MATCH',round(best[2],3) if best else 0,n,''])
        print(f"  {jp} {name} → NO_MATCH best={best[2] if best else 0:.3f} (후보{n})")

with open('/Users/fury/pokemon-card-app/python/catalog_gapfill/en_rematch_result.csv','w',newline='') as f:
    w=csv.writer(f); w.writerow(['jp_ref','en_name','en_ref','cosine','candidates','scrydex_img']); w.writerows(rows)
ok=sum(1 for r in rows if str(r[2]).count('-')>=1 and r[2] not in ('NO_MATCH','API_FAIL','JP_IMG_FAIL'))
print(f"\n매칭 성공 {ok}/{len(rows)} → en_rematch_result.csv")
