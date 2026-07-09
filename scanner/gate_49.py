#!/usr/bin/env python3
"""49장 배포 합격 게이트: 집합·기존불변 + 3840(.bak) 재측정 A/B + 8건복귀 + 49 self-match + 맥날/탱탱겔."""
import sys, json, os, glob, collections, numpy as np, cv2, torch, faiss
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
sys.path.insert(0,'/Users/fury/pokemon-card-app/scanner'); from app.detector import CardDetector
proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base"); mdl=AutoModel.from_pretrained("model/dinov2_finetuned").eval()
det=CardDetector()
BAK=sorted(glob.glob('db/card_db.faiss.bak_pre53_*'))[-1]; BAKM=sorted(glob.glob('db/card_meta.json.bak_pre53_*'))[-1]
base=faiss.read_index(BAK); bmeta=json.load(open(BAKM)); BV=list(bmeta['vectors'])
test=faiss.read_index('db/card_db.faiss'); tmeta=json.load(open('db/card_meta.json')); TV=list(tmeta['vectors'])
EXC={'CRD_555EE842647815F48715','CRD_C25940958F57A0DE60C8','CRD_7EFC022C360ECB18F368','CRD_07838391EB0EE31C2240'}
new53=set(json.load(open('/tmp/build53_ids.json'))); new49=new53-EXC
db=set(l.strip() for l in open('/tmp/db3893.txt') if l.strip())
tset=set(TV); bvc=collections.Counter(BV); tvc=collections.Counter(TV)
print("=== 게이트1: 집합·기존불변 ===")
print(f"  scanner {len(tset)} (3889기대) · DB {len(db)} (3893) · DB-scanner diff {len(db-tset)} (4기대)")
print(f"  diff==제외4장: {(db-tset)==EXC} · orphan {len(tset-db)} · <10벡터 {sum(1 for c in tset if tvc[c]<10)}")
print(f"  신규49 존재 {sum(1 for c in new49 if c in tset)}/49 · 제외4 부재 {sum(1 for c in EXC if c not in tset)}/4")
chg=[c for c in set(BV) if tvc[c]!=bvc[c]]; print(f"  기존3840 vector_count 변동 {len(chg)} · prefix불변 {TV[:len(BV)]==BV}")
def r1600(i):
    h,w=i.shape[:2]; return i if max(h,w)<=1600 else cv2.resize(i,(int(w*1600/max(h,w)),int(h*1600/max(h,w))),interpolation=cv2.INTER_AREA)
def emb(i):
    inp=proc(images=Image.fromarray(cv2.cvtColor(i,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**inp)
    e=torch.cat([o.last_hidden_state[:,0,:],o.last_hidden_state[:,1:,:].mean(1)],-1).numpy()[0]; return (e/(np.linalg.norm(e)+1e-8)).astype(np.float32)
def t1(index,V,e):
    sc,ix=index.search(e.reshape(1,-1),50); best={}
    for s,j in zip(sc[0],ix[0]):
        if j<0: continue
        c=V[j]
        if c not in best or s>best[c]: best[c]=float(s)
    return max(best,key=best.get) if best else None
def E(p):
    img=cv2.imread(p)
    if img is None: return None
    img=r1600(img); w,_=det.find_and_warp_card(img); return emb(w if w is not None else img)
# 쿼리셋
idx=set(BV); m46=json.load(open('/Users/fury/pokemon-card-app/python/catalog_gapfill/approved_46_final_manifest.json'))
Q=[]
for d in os.listdir('data/scan_captures'):
    if d in idx:
        for c in glob.glob(f'data/scan_captures/{d}/*.jpg'): Q.append((c,d,'scan'))
for d in os.listdir('data/realshots'):
    if d in idx:
        fs=sorted(glob.glob(f'data/realshots/{d}/*.jpg'))
        if fs: Q.append((fs[0],d,'realshot'))
for x in m46:
    for s in('ko','jp','en'):
        p=f"data/cards/{x['card_id']}_{s}.png"; p=p+'.bad_warp' if(not os.path.exists(p) and s=='ko') else p
        if os.path.exists(p): Q.append((p,x['card_id'],'new46'))
for cid in new49:
    for s in('ko','jp','en'):
        p=f"data/cards/{cid}_{s}.png"
        if os.path.exists(p): Q.append((p,cid,'new49'))
print(f"\n=== 게이트2-5: A/B (3840 vs 3889) {len(Q)}쿼리 ===")
agg=collections.defaultdict(lambda:[0,0,0])
reg8=set(json.load(open('/tmp/reg8_paths.json'))); reg_ret=[]
newreg=[]
for p,exp,src in Q:
    e=E(p)
    if e is None: continue
    bt=t1(base,BV,e) if src in('scan','realshot','new46') else None
    tt=t1(test,TV,e); a=agg[src]
    if bt is not None: a[0]+=(bt==exp)
    a[1]+=(tt==exp); a[2]+=1
    if bt is not None and bt==exp and tt!=exp: newreg.append((src,p.split('/')[-1],tt))
    if p in reg8: reg_ret.append((p.split('/')[-1],tt==exp))
for s in['scan','realshot','new46']:
    a=agg[s]; print(f"  {s:9} 3840 {a[0]}/{a[2]} → 3889 {a[1]}/{a[2]}  신규회귀 {'0✅' if a[1]>=a[0] else str(a[1]-a[0])+'❌'}")
print(f"  new49 self-match: {agg['new49'][1]}/{agg['new49'][2]} (147기대)")
print(f"  ★3889 신규회귀 총: {len(newreg)} {'✅' if not newreg else newreg[:5]}")
print(f"  ★회귀8건 정답복귀: {sum(1 for _,ok in reg_ret if ok)}/8")
print("\n=== 게이트5: 맥날·탱탱겔 ===")
for nm,pp,exp in [('맥날','/tmp/mcd_clean.png','CRD_B44585853A93C37F791B552F69C70AA6'),('탱탱겔','data/cards/CRD_A52ADAD23735C0E3C95C_ko.png.bad_warp','CRD_A52ADAD237')]:
    if os.path.exists(pp):
        tt=t1(test,TV,E(pp)); print(f"  {nm}: {tt[:14] if tt else '?'} {'✅' if tt and tt.startswith(exp[:14]) else '❌'}")
