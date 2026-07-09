#!/usr/bin/env python3
"""회귀 8건 벡터 단위 + OCR 포렌식. /identify 전체경로 복제(resize1600+warp+emb+raw FAISS+OCR).
오답 Top-1의 신규 card_id·source(JP/EN/KO)·augmentation·cosine + 정답카드 점수분포 + OCR번호 + rerank로 해결되는지."""
import sys, json, re, numpy as np, cv2, torch, faiss
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
sys.path.insert(0, '/Users/fury/pokemon-card-app/scanner')
from app.detector import CardDetector

proc=AutoImageProcessor.from_pretrained("facebook/dinov2-base"); mdl=AutoModel.from_pretrained("model/dinov2_finetuned").eval()
det=CardDetector(); index=faiss.read_index("db/card_db.faiss"); meta=json.load(open("db/card_meta.json")); V=meta['vectors']
start={}
for i,c in enumerate(V):
    if c not in start: start[c]=i   # 첫 등장(연속 가정)
import easyocr; reader=easyocr.Reader(["en"],gpu=False,verbose=False)
# 기존 officialCode (정답 카드)
OFF={'CRD_90698EA0987C4C82913F':'BS2022002107','CRD_3EC2D5FC5CD94A18B44E':'BS2020016324','CRD_17EF823FA3CB4B2B8EE4':'BS2011003069','CRD_3392C238DFEC4357BA88':None}
def resize1600(img):
    h,w=img.shape[:2]
    if max(h,w)<=1600: return img
    s=1600/max(h,w); return cv2.resize(img,(int(w*s),int(h*s)),interpolation=cv2.INTER_AREA)
def emb(img):
    inp=proc(images=Image.fromarray(cv2.cvtColor(img,cv2.COLOR_BGR2RGB)),return_tensors="pt")
    with torch.no_grad(): o=mdl(**inp)
    cls=o.last_hidden_state[:,0,:]; pm=o.last_hidden_state[:,1:,:].mean(1)
    e=torch.cat([cls,pm],-1).numpy()[0]; return (e/(np.linalg.norm(e)+1e-8)).astype(np.float32)
def ocr_num(w):
    h,wd=w.shape[:2]; b=w[int(h*0.87):,:]; bu=cv2.resize(b,(wd*2,b.shape[0]*2))
    t=" ".join(reader.readtext(bu,detail=0,allowlist="0123456789/")); m=re.search(r'(\d{3})\s*/\s*\d{3}',t)
    return m.group(1) if m else None, t
def srcaug(pos):
    if pos<0 or pos>=15: return f'pos{pos}','?'
    return ['JP','EN','KO'][pos//5], ['orig','bright','dark','rot+','rot-'][pos%5]
for path in json.load(open('/tmp/reg8_paths.json')):
    cc=path.split('/')[2]  # 정답 card_id (폴더)
    img=cv2.imread(path)
    if img is None: print(f"  {path}: 이미지없음"); continue
    img=resize1600(img); warped,_=det.find_and_warp_card(img)
    if warped is None: warped=img
    e=emb(warped); sc,ix=index.search(e.reshape(1,-1),30)
    t1i=int(ix[0][0]); t1c=V[t1i]; t1s=float(sc[0][0]); pos=t1i-start.get(t1c,t1i); src,aug=srcaug(pos)
    # 정답 카드 best
    ccs=[float(sc[0][j]) for j,k in enumerate(ix[0]) if V[k]==cc]
    ccbest=max(ccs) if ccs else None
    onum,otext=ocr_num(warped)
    off=OFF.get(cc); ocr_match = (onum and off and off[-3:].lstrip('0')==onum.lstrip('0'))
    fixable = ccbest is not None and ocr_match and (ccbest+0.12)>t1s
    ccb = f"{ccbest:.3f}" if ccbest is not None else "top30밖"
    print(f"\n  {path.split('/')[-1]} (정답 {cc[:12]})")
    print(f"    오답 Top-1: {t1c[:12]} score={t1s:.3f} · source={src} aug={aug} (신규벡터 pos{pos})")
    print(f"    정답 best score: {ccb}")
    print(f"    OCR 추출='{otext.strip()[:30]}' 번호={onum} · 정답official={off} 매칭={ocr_match}")
    if ccbest is not None:
        print(f"    → OCR rerank로 해결가능: {fixable} (정답+0.12={ccbest+0.12:.3f} vs 오답{t1s:.3f})")
