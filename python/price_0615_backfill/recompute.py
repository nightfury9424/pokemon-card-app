#!/usr/bin/env python3
# 14/15/16 KO 로컬 재산출 — GlobalPriceService 충실 재현.
# 선택: suspect(jp/en>8 or jp>cap) → spread(2.0/2.2/1.8, prevSource). KO=raw_krw×coef.
# prevSource 체인: s13 → 14 → 15 → 16 (6/15 채워 6/16 flip 제거).
import csv, os
D = os.path.dirname(__file__)

# FX: 저장값/100 = 실환율
fx = {}
for line in open(os.path.join(D, 'fx.csv')):
    line = line.strip()
    if not line: continue
    dt, cid, price = line.split('|')
    cur = 'USD' if 'usd' in cid else 'JPY'
    fx.setdefault(dt, {})[cur] = float(price) / 100.0
DAYS = ['2026-06-14', '2026-06-15', '2026-06-16']

CAP = {'HR':2_000_000,'MUR':2_000_000,'SR':5_000_000,'SAR':5_000_000,'SSR':5_000_000}
def cap(r): return CAP.get(r, 3_000_000)

def rawkrw(native, curr, pricekrw, f):
    if native and curr in ('USD','JPY'): return float(native)*f[curr]
    if curr=='KRW' and native: return float(native)
    if pricekrw: return float(pricekrw)   # fallback: stored KRW
    return None

def suspect(jpk, enk, rarity):
    if jpk is None: return True
    if enk and enk>0 and jpk/enk > 8.0: return True
    if jpk > cap(rarity): return True
    return False

def select(jpk, enk, rarity, prev):
    # returns 'JP' or 'EN' or None
    if jpk is not None and not suspect(jpk, enk, rarity):
        if enk is not None:
            lo, hi = min(jpk,enk), max(jpk,enk)
            th = 2.2 if prev=='JP' else (1.8 if prev=='EN' else 2.0)
            return 'EN' if (lo>0 and hi/lo>th) else 'JP'
        return 'JP'
    return 'EN' if enk is not None else None

rows=[]
for line in open(os.path.join(D,'cards_wide.csv')):
    p=line.rstrip('\n').split('|')
    if len(p)<15: continue
    cid,rar,jn,jc,jpk,en_,ec,epk,s13,c14,s14,k14,k16,s16,c16 = p
    def fl(x): return float(x) if x else None
    rows.append(dict(cid=cid,rar=rar,jn=fl(jn),jc=jc,jpk=fl(jpk),en=fl(en_),ec=ec,epk=fl(epk),
                     s13=s13 or None,c14=fl(c14),s14=s14 or None,k14=fl(k14),
                     k16=fl(k16),s16=s16 or None,c16=fl(c16)))

def coef_for(r, src):
    # per-card 계수 (c14/c16에서 양쪽 소스 확보)
    cj = r['c14'] if r['s14']=='JP' else (r['c16'] if r['s16']=='JP' else None)
    ce = r['c14'] if r['s14']=='EN' else (r['c16'] if r['s16']=='EN' else None)
    return cj if src=='JP' else ce

def compute_day(r, day, prev):
    f=fx[day]
    jpk=rawkrw(r['jn'],r['jc'],r['jpk'],f)
    enk=rawkrw(r['en'],r['ec'],r['epk'],f)
    src=select(jpk,enk,r['rar'],prev)
    if src is None: return None,None
    rk = jpk if src=='JP' else enk
    cf = coef_for(r,src)
    if cf is None or rk is None: return src,None
    return src, round(rk*cf)

# ---- 6/14 검증 (prev=s13) ----
src_ok=ko_ok=tot=ko_have=0
for r in rows:
    if r['k14'] is None: continue
    tot+=1
    src,ko=compute_day(r,'2026-06-14',r['s13'])
    if src==r['s14']: src_ok+=1
    if ko is not None:
        ko_have+=1
        if abs(ko-r['k14'])<=max(2, r['k14']*0.02): ko_ok+=1
print(f"[6/14 검증] n={tot}  source일치={src_ok}({100*src_ok/tot:.1f}%)  ko일치={ko_ok}/{ko_have}({100*ko_ok/ko_have:.1f}%)")

# ---- meta (name, 현재표시값) ----
name={}; disp={}
for line in open(os.path.join(D,'meta.csv')):
    p=line.rstrip('\n').split('|')
    if len(p)<3: continue
    name[p[0]]=p[1]; disp[p[0]]=float(p[2]) if p[2] else None

def ratio_of(r):
    f=fx['2026-06-16']
    jpk=rawkrw(r['jn'],r['jc'],r['jpk'],f); enk=rawkrw(r['en'],r['ec'],r['epk'],f)
    if jpk and enk and min(jpk,enk)>0: return round(max(jpk,enk)/min(jpk,enk),2)
    return None

# ---- 체인 재산출 + source기반 분류 (value는 노이즈라 분류근거로 안 씀) ----
# 교정값 = prod validated 6/14 JP값(k14) carry. recomp_k16은 참고용(±노이즈).
out=[]; cnt={}
for r in rows:
    s14c,k14c=compute_day(r,'2026-06-14',r['s13'])
    s15c,k15c=compute_day(r,'2026-06-15',s14c)
    s16c,k16c=compute_day(r,'2026-06-16',s15c)
    rat=ratio_of(r)
    flipped = (r['s14']=='JP' and r['s16']=='EN')   # 6/14 JP → 6/16 EN = 폭등 (Codex 95)
    if flipped and s16c=='JP':   act='FIX_TO_JP'        # prevSource 고치면 좋은코드가 JP복원
    elif flipped:                act='ANCHOR_NEEDED'    # ratio>2.2 → 좋은코드도 EN고집 → 수동앵커
    elif r['s16']=='JP':         act='LEAVE_JP'         # 이미 JP (정책상 OK)
    elif r['s16']=='EN':         act='LEAVE_EN'         # 14·16 둘다 EN (원래 EN)
    else:                        act='OTHER'
    cnt[act]=cnt.get(act,0)+1
    correct = int(r['k14']) if (act in ('FIX_TO_JP','ANCHOR_NEEDED') and r['k14']) else ''
    out.append([r['cid'],name.get(r['cid'],''),r['rar'],r['s14'],r['s16'],s16c,
                int(r['k14']) if r['k14'] else '', int(r['k16']) if r['k16'] else '',
                int(disp[r['cid']]) if disp.get(r['cid']) is not None else '',
                int(k16c) if k16c is not None else '', rat if rat else '', correct, act])
order={'FIX_TO_JP':0,'ANCHOR_NEEDED':1,'LEAVE_EN':2,'LEAVE_JP':3,'OTHER':4}
out.sort(key=lambda x:(order.get(x[12],9), -(x[7] if isinstance(x[7],int) else 0)))
hdr=['card_id','name','rarity','prod_s14','prod_s16','recomp_s16','k14_lastgoodJP','audit_k16',
     'display_now','recomp_k16(ref)','ratio','correct_val(=k14)','action']
with open(os.path.join(D,'recompute_full.csv'),'w',newline='') as fo:
    w=csv.writer(fo); w.writerow(hdr); w.writerows(out)
print("[종합 action별]", cnt)
print("  FIX_TO_JP + ANCHOR_NEEDED =", cnt.get('FIX_TO_JP',0)+cnt.get('ANCHOR_NEEDED',0), "(=6/14 JP→6/16 EN 폭등, Codex 95와 대조)")
print("→ recompute_full.csv 저장 (전", len(out), "장)")
