#!/usr/bin/env python3
"""KO 원본=진실원 기준 JP·EN 재매칭 + 승인 HTML 생성 (자동반영 X, 사용자 승인용).
- EN: scrydex 타이틀로 EN명 → pokemontcg.io 검색 → 각 후보 DINOv2 vs KO → best.
- JP: KO↔JP<0.78(명백오류)만 같은 세트 이미지 enumerate → DINOv2 vs KO → best. 그외 현재 유지.
입력 /tmp/rematch_input.json. 출력 kotruth_rematch_review.html (검수→JSON export)."""
import urllib.request, urllib.parse, json, re, html as _html, numpy as np, cv2, torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
UA={'User-Agent':'Mozilla/5.0 Chrome/120'}
def get(u):
    try: return urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=25).read().decode('utf-8','ignore')
    except Exception: return ''
def jget(u): return json.load(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=30))
def dl(u):
    try: return cv2.imdecode(np.frombuffer(urllib.request.urlopen(urllib.request.Request(u,headers=UA),timeout=20).read(),np.uint8),cv2.IMREAD_COLOR)
    except Exception: return None
def scry_img(ref): return f"https://images.scrydex.com/pokemon/{ref}/medium"
def scry_title(ref):
    h=get(f"https://scrydex.com/pokemon/cards/_/{ref}"); m=re.search(r'<title>([^<|]+)',h)
    return re.sub(r'\s*[·#].*$','',_html.unescape(m.group(1))).strip() if m else ''

proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base")
mdl=AutoModel.from_pretrained("/Users/fury/pokemon-card-app/scanner/model/dinov2_finetuned").eval()
_cache={}
def emb_url(u):
    if u in _cache: return _cache[u]
    im=dl(u)
    if im is None: _cache[u]=None; return None
    i=proc(images=Image.fromarray(cv2.cvtColor(im,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**i)
    v=o.last_hidden_state[:,0,:].numpy()[0]; v=v/np.linalg.norm(v); _cache[u]=v; return v
def cos(a,b): return float(np.dot(a,b)) if a is not None and b is not None else 0.0

cards=json.load(open("/tmp/rematch_input.json"))
out=[]
for c in cards:
    koe=emb_url(c['ko_img'])
    setp=c['jp_ref'].rsplit('-',1)[0]; curnum=c['jp_ref'].rsplit('-',1)[1]
    konum=re.sub(r'\D','',str(c.get('ko_no','')))
    # JP
    cur_jp_score=round(cos(koe,emb_url(scry_img(c['jp_ref']))),3)
    jp_prop=None
    if c.get('ko_jp') is not None and c['ko_jp']<0.78:
        cand=set([f"{setp}-{konum}"])
        for n in range(max(1,int(re.sub(r'\D','',curnum) or 0)-6), int(re.sub(r'\D','',curnum) or 0)+7): cand.add(f"{setp}-{n}")
        if konum:
            for n in range(max(1,int(konum)-6), int(konum)+7): cand.add(f"{setp}-{n}")
        best=None
        for r in cand:
            e=emb_url(scry_img(r))
            if e is None: continue
            sc=cos(koe,e)
            if best is None or sc>best[1]: best=(r,sc)
        if best and best[1]>cur_jp_score: jp_prop={'ref':best[0],'score':round(best[1],3)}
    # EN — 수정된 JP(클린 스캔) 기준 매칭 + KO↔EN 병기. EN명도 수정 JP 타이틀에서.
    final_jp=jp_prop['ref'] if jp_prop else c['jp_ref']
    jpe=emb_url(scry_img(final_jp))
    enname=scry_title(final_jp)
    en_prop=None
    if enname:
        try:
            r=jget(f"https://api.pokemontcg.io/v2/cards?q={urllib.parse.quote('name:'+chr(34)+enname+chr(34))}&pageSize=120")
            best=None
            for cc in r.get('data',[]):
                e=emb_url(cc['images']['large'])
                if e is None: continue
                sj=cos(jpe,e)
                if best is None or sj>best[1]: best=(f"{cc['set']['id']}-{cc.get('number')}",sj,cc['images']['large'],round(cos(koe,e),3))
            if best and best[1]>=0.85: en_prop={'ref':best[0],'score':round(best[1],3),'img':best[2],'ko':best[3]}
        except Exception: pass
    out.append({**c,'cur_jp_score':cur_jp_score,'jp_prop':jp_prop,'en_name':enname,'en_prop':en_prop})
    print(f"  {c['ko_name']} ({c['rarity']}) curJP={cur_jp_score}{' JP→'+jp_prop['ref']+'('+str(jp_prop['score'])+')' if jp_prop else ''} | EN={enname}→{en_prop['ref']+'('+str(en_prop['score'])+')' if en_prop else 'NO_MATCH'}")
json.dump(out,open("/tmp/rematch_proposals.json","w"),ensure_ascii=False)
print(f"\n  {len(out)}장 → /tmp/rematch_proposals.json")
