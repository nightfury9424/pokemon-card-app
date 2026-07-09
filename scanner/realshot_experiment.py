#!/usr/bin/env python3
"""실사진 augment10 → 8종에 추가한 테스트 인덱스 vs baseline(3893) A/B. write-0(prod·로컬인덱스 불변, 메모리상 테스트)."""
import sys, json, os, glob, base64, numpy as np, cv2, torch, faiss
from PIL import Image
from collections import defaultdict
from transformers import AutoImageProcessor, AutoModel
sys.path.insert(0,'/Users/fury/pokemon-card-app/scanner'); from app.detector import CardDetector
proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base"); mdl=AutoModel.from_pretrained("model/dinov2_finetuned").eval()
det=CardDetector(); meta=json.load(open("db/card_meta.json")); BV=list(meta['vectors'])
def resize1600(img):
    h,w=img.shape[:2]
    return img if max(h,w)<=1600 else cv2.resize(img,(int(w*1600/max(h,w)),int(h*1600/max(h,w))),interpolation=cv2.INTER_AREA)
def emb(img):
    inp=proc(images=Image.fromarray(cv2.cvtColor(img,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**inp)
    e=torch.cat([o.last_hidden_state[:,0,:],o.last_hidden_state[:,1:,:].mean(1)],-1).numpy()[0]
    return (e/(np.linalg.norm(e)+1e-8)).astype(np.float32)
def augment10(bgr):
    h,w=bgr.shape[:2]; out=[bgr]
    for b in(55,-55,28,-28): out.append(cv2.convertScaleAbs(bgr,alpha=1.0,beta=b))
    for d in(7,-7,14,-14):
        M=cv2.getRotationMatrix2D((w/2,h/2),d,1.0); out.append(cv2.warpAffine(bgr,M,(w,h),borderMode=cv2.BORDER_REPLICATE))
    m=int(min(h,w)*0.04); out.append(cv2.resize(bgr[m:h-m,m:w-m],(w,h))); return out
# 실사진 처리 → augment10 벡터
crops=json.load(open('/Users/fury/Downloads/realshots_crops.json'))
rs_cid=[]; rs_vec=[]; hold={}  # holdout: 카드별 마지막 1장은 검증 전용(인덱스 미포함)
print("실사진 augment10 처리...")
for cid,v in crops.items():
    imgs=[cv2.imdecode(np.frombuffer(base64.b64decode(b.split(',')[1]),np.uint8),cv2.IMREAD_COLOR) for b in v['images']]
    hold[cid]=imgs[-1] if len(imgs)>=3 else None  # 3장이상이면 1장 holdout
    use=imgs[:-1] if hold[cid] is not None else imgs
    for im in use:
        if im is None: continue
        im=resize1600(im); w,_=det.find_and_warp_card(im); w=w if w is not None else im
        for a in augment10(w): rs_cid.append(cid); rs_vec.append(emb(a))
print(f"  추가 벡터 {len(rs_vec)} (holdout {sum(1 for h in hold.values() if h is not None)}장 인덱스 제외)")
# 인덱스: baseline=3893, test=3893+실사진
base=faiss.read_index("db/card_db.faiss"); test=faiss.read_index("db/card_db.faiss")
test.add(np.array(rs_vec).astype('float32')); TV=BV+rs_cid
def top1(index,V,e):
    sc,ix=index.search(e.reshape(1,-1),50); best={}
    for s,j in zip(sc[0],ix[0]):
        if j<0: continue
        c=V[j];
        if c not in best or s>best[c]: best[c]=float(s)
    return max(best.items(),key=lambda x:x[1]) if best else (None,0)
# 쿼리셋
idx=set(BV); m46=json.load(open('/Users/fury/pokemon-card-app/python/catalog_gapfill/approved_46_final_manifest.json'))
new53=set(json.load(open('/tmp/build53_ids.json'))); reg8=json.load(open('/tmp/reg8_paths.json'))
Q=[]
for d in os.listdir('data/scan_captures'):
    if d in idx:
        for c in glob.glob(f'data/scan_captures/{d}/*.jpg'): Q.append((c,d,'scan'))
for d in os.listdir('data/realshots'):
    if d in idx:
        fs=sorted(glob.glob(f'data/realshots/{d}/*.jpg'));
        if fs: Q.append((fs[0],d,'realshot'))
for x in m46:
    for s in('ko','jp','en'):
        p=f"data/cards/{x['card_id']}_{s}.png"; p=p+'.bad_warp' if (not os.path.exists(p) and s=='ko') else p
        if os.path.exists(p): Q.append((p,x['card_id'],'new46'))
for cid in new53:
    for s in('ko','jp','en'):
        p=f"data/cards/{cid}_{s}.png"
        if os.path.exists(p): Q.append((p,cid,'new53'))
print(f"쿼리 {len(Q)} A/B...")
agg=defaultdict(lambda:[0,0,0])  # src:[baseOK,testOK,n]
reg8set=set(reg8); reg_fixed=[]
for i,(p,exp,src) in enumerate(Q):
    img=cv2.imread(p);
    if img is None: continue
    img=resize1600(img); w,_=det.find_and_warp_card(img); w=w if w is not None else img
    e=emb(w); bt,_=top1(base,BV,e); tt,_=top1(test,TV,e)
    a=agg[src]; a[0]+=(bt==exp); a[1]+=(tt==exp); a[2]+=1
    if p in reg8set: reg_fixed.append((p.split('/')[-1],bt==exp,tt==exp))
    if (i+1)%400==0: print(f"  ...{i+1}/{len(Q)}")
print("\n=== A/B (baseline 3893 vs +실사진) ===")
for s in['scan','realshot','new46','new53']:
    a=agg[s]; print(f"  {s:9} baseline {a[0]}/{a[2]} → +실사진 {a[1]}/{a[2]}  ({'+' if a[1]>=a[0] else ''}{a[1]-a[0]})")
print("\n=== 회귀 8건 개별 (baseline 오답 → 실사진후) ===")
for nm,bok,tok in reg_fixed: print(f"  {nm}: {'해결✅' if tok else '여전오답'}")
# holdout 검증
print("\n=== holdout(인덱스 미포함 실사진) 검증 ===")
for cid,h in hold.items():
    if h is None: continue
    im=resize1600(h); w,_=det.find_and_warp_card(im); w=w if w is not None else im
    e=emb(w); bt,bs=top1(base,BV,e); tt,ts=top1(test,TV,e)
    nm=crops[cid]['name']
    print(f"  {nm}: baseline→{bt[:12] if bt else '?'}({bs:.2f}) {'✅' if bt==cid else '❌'} | +실사진→{tt[:12] if tt else '?'}({ts:.2f}) {'✅' if tt==cid else '❌'}")
