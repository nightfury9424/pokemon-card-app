#!/usr/bin/env python3
"""A/B write-0 실험: raw FAISS Top-K를 card별로 묶어 여러 스코어링 방식 비교 (인덱스/main.py 불변).
baseline=max(현재) · A=rot+7제외(문제4장) · B_top2/top3=상위N평균 · B_outlier=튀는벡터제외.
고정셋: scan_capture·realshots·new46·new53 KO/JP/EN. 출력=방식별 정확도/회귀/시간."""
import sys, json, os, glob, time, numpy as np, cv2, torch, faiss
from PIL import Image
from collections import defaultdict
from transformers import AutoImageProcessor, AutoModel
sys.path.insert(0,'/Users/fury/pokemon-card-app/scanner'); from app.detector import CardDetector
proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base"); mdl=AutoModel.from_pretrained("model/dinov2_finetuned").eval()
det=CardDetector(); index=faiss.read_index("db/card_db.faiss"); meta=json.load(open("db/card_meta.json")); V=meta['vectors']
start={}
for i,c in enumerate(V):
    if c not in start: start[c]=i
# rot+7 제외 대상 = 문제4장의 pos3,8,13 (JP/EN/KO rot+)
PROB4=['CRD_555EE842647815F48715','CRD_C25940958F57A0DE60C8','CRD_7EFC022C360ECB18F368','CRD_07838391EB0EE31C2240']
rotplus_idx=set()
for c in PROB4:
    for p in (3,8,13): rotplus_idx.add(start[c]+p)
def resize1600(img):
    h,w=img.shape[:2]
    return img if max(h,w)<=1600 else cv2.resize(img,(int(w*1600/max(h,w)),int(h*1600/max(h,w))),interpolation=cv2.INTER_AREA)
def emb(img):
    inp=proc(images=Image.fromarray(cv2.cvtColor(img,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**inp)
    e=torch.cat([o.last_hidden_state[:,0,:],o.last_hidden_state[:,1:,:].mean(1)],-1).numpy()[0]
    return (e/(np.linalg.norm(e)+1e-8)).astype(np.float32)
# 쿼리셋
m46=json.load(open('/Users/fury/pokemon-card-app/python/catalog_gapfill/approved_46_final_manifest.json'))
new53=set(json.load(open('/tmp/build53_ids.json')))
idx=set(V)
queries=[]
for d in os.listdir('data/scan_captures'):
    if d in idx:
        for c in glob.glob(f'data/scan_captures/{d}/*.jpg'): queries.append((c,d,'scan_capture'))
for d in os.listdir('data/realshots'):
    if d in idx:
        fs=sorted(glob.glob(f'data/realshots/{d}/*.jpg'))
        if fs: queries.append((fs[0],d,'realshot'))
for x in m46:
    for sfx in ('ko','jp','en'):
        p=f"data/cards/{x['card_id']}_{sfx}.png"
        if not os.path.exists(p) and sfx=='ko': p+='.bad_warp'
        if os.path.exists(p): queries.append((p,x['card_id'],'new46_'+sfx))
for cid in new53:
    for sfx in ('ko','jp','en'):
        p=f"data/cards/{cid}_{sfx}.png"
        if os.path.exists(p): queries.append((p,cid,'new53_'+sfx))
print(f"쿼리 {len(queries)}개 임베딩+raw search...")
# 임베딩 1회 + raw Top-200
raw=[]; t0=time.time()
for i,(p,exp,src) in enumerate(queries):
    img=cv2.imread(p)
    if img is None: continue
    img=resize1600(img); w,_=det.find_and_warp_card(img); w=w if w is not None else img
    e=emb(w); sc,ix=index.search(e.reshape(1,-1),200)
    raw.append((exp,src,[(int(j),float(s)) for s,j in zip(sc[0],ix[0]) if j>=0]))
    if (i+1)%300==0: print(f"  ...{i+1}/{len(queries)}")
print(f"  임베딩 완료 {time.time()-t0:.0f}s")
# 스코어링 방식
def topk_by_card(results, excl=None, k=1, outlier=False):
    byc=defaultdict(list)
    for j,s in results:
        if excl and j in excl: continue
        byc[V[j]].append(s)
    out={}
    for c,ss in byc.items():
        ss=sorted(ss,reverse=True)
        if outlier and len(ss)>=2 and (ss[0]-ss[1])>0.10: ss=ss[1:]  # 튀는 1개 제외
        out[c]=float(np.mean(ss[:k])) if k>1 else ss[0]
    return max(out.items(),key=lambda x:x[1])[0] if out else None
METHODS={'baseline_max':lambda r:topk_by_card(r,k=1),
 'A_rotplus제외':lambda r:topk_by_card(r,excl=rotplus_idx,k=1),
 'B_top2avg':lambda r:topk_by_card(r,k=2),
 'B_top3avg':lambda r:topk_by_card(r,k=3),
 'B_outlier제외':lambda r:topk_by_card(r,outlier=True,k=1),
 'AB_rot제외+top2':lambda r:topk_by_card(r,excl=rotplus_idx,k=2)}
# 평가
print("\n=== 방식별 정확도 (정답=Top-1) ===")
hdr=f"  {'방식':18}{'scan_cap':10}{'realshot':10}{'new46':9}{'new53':9}"
print(hdr)
for name,fn in METHODS.items():
    agg=defaultdict(lambda:[0,0])
    for exp,src,results in raw:
        ok=fn(results)==exp; key=src.split('_')[0]
        agg[key][0]+=ok; agg[key][1]+=1
    def pct(k): a=agg[k]; return f"{a[0]}/{a[1]}"
    sc=pct('scan'); rs=pct('realshot'); n46=sum(agg[k][0] for k in agg if k=='new46')
    n46t=sum(agg[k][1] for k in agg if k=='new46'); n53=agg['new53'][0]; n53t=agg['new53'][1]
    print(f"  {name:18}{sc:10}{rs:10}{str(n46)+'/'+str(n46t):9}{str(n53)+'/'+str(n53t):9}")
print("\n  (scan_cap 기준 baseline 대비 회귀 0 + new53 유지가 합격)")
