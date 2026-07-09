#!/usr/bin/env python3
"""진단: 8스캔이 ①정답 실사진 ②정답 클린 ③신규 클린 중 무엇에 얼마나 붙나 + 정답쪽만 실사진추가시 해결되나."""
import sys, json, base64, numpy as np, cv2, torch, faiss
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
sys.path.insert(0,'/Users/fury/pokemon-card-app/scanner'); from app.detector import CardDetector
proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base"); mdl=AutoModel.from_pretrained("model/dinov2_finetuned").eval()
det=CardDetector(); meta=json.load(open("db/card_meta.json")); BV=list(meta['vectors'])
base=faiss.read_index("db/card_db.faiss"); allv=base.reconstruct_n(0,base.ntotal)  # 3893 벡터 행렬
def r1600(i):
    h,w=i.shape[:2]; return i if max(h,w)<=1600 else cv2.resize(i,(int(w*1600/max(h,w)),int(h*1600/max(h,w))),interpolation=cv2.INTER_AREA)
def emb(i):
    inp=proc(images=Image.fromarray(cv2.cvtColor(i,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**inp)
    e=torch.cat([o.last_hidden_state[:,0,:],o.last_hidden_state[:,1:,:].mean(1)],-1).numpy()[0]; return (e/(np.linalg.norm(e)+1e-8)).astype(np.float32)
def aug10(b):
    h,w=b.shape[:2]; o=[b]
    for x in(55,-55,28,-28): o.append(cv2.convertScaleAbs(b,alpha=1.0,beta=x))
    for d in(7,-7,14,-14): M=cv2.getRotationMatrix2D((w/2,h/2),d,1.0); o.append(cv2.warpAffine(b,M,(w,h),borderMode=cv2.BORDER_REPLICATE))
    m=int(min(h,w)*0.04); o.append(cv2.resize(b[m:h-m,m:w-m],(w,h))); return o
PAIRS={'CRD_90698EA0987C4C82913F':'CRD_555EE842647815F48715','CRD_3EC2D5FC5CD94A18B44E':'CRD_C25940958F57A0DE60C8','CRD_17EF823FA3CB4B2B8EE4':'CRD_7EFC022C360ECB18F368','CRD_3392C238DFEC4357BA88':'CRD_07838391EB0EE31C2240'}
crops=json.load(open('/Users/fury/Downloads/realshots_crops.json'))
# 정답카드 실사진 벡터 (전부 사용, 진단용)
rsvec={}
for cid in PAIRS:
    vs=[]
    for b in crops[cid]['images']:
        im=cv2.imdecode(np.frombuffer(base64.b64decode(b.split(',')[1]),np.uint8),cv2.IMREAD_COLOR)
        if im is None: continue
        im=r1600(im); w,_=det.find_and_warp_card(im); w=w if w is not None else im
        for a in aug10(w): vs.append(emb(a))
    rsvec[cid]=np.array(vs)
# 카드별 클린벡터 인덱스
byc={}
for i,c in enumerate(BV): byc.setdefault(c,[]).append(i)
def cleanmax(cid,e):
    idx=byc.get(cid,[]); return float(max((allv[idx]@e)).item()) if idx else 0
for path in json.load(open('/tmp/reg8_paths.json')):
    cc=path.split('/')[2]; nw=PAIRS[cc]
    img=cv2.imread(path); img=r1600(img); w,_=det.find_and_warp_card(img); w=w if w is not None else img
    e=emb(w)
    s_rs=float(max((rsvec[cc]@e)).item()) if len(rsvec[cc]) else 0
    s_cc=cleanmax(cc,e); s_nw=cleanmax(nw,e)
    win = '정답✅' if (max(s_rs,s_cc)>s_nw) else '신규❌'
    print(f"  {path.split('/')[-1]}: 정답실사진 {s_rs:.3f} · 정답클린 {s_cc:.3f} · 신규클린 {s_nw:.3f} → 정답쪽만추가시 {win}")
