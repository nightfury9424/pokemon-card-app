#!/usr/bin/env python3
"""scrydex JP ladder 이상치 추출. 분석 전용 — DB write 0, 가격 반영 0, 대체 적용 0.
정상 ladder = PSA10 > PSA9 > RAW (데이터 84% 확인). 이상치만 추려 SNK 교정 후보화.
"""
import csv
from collections import defaultdict

LAD="python/price_v8/scrydex_jp_ladder_prod.csv"   # card_id,tier,latest,med30,n30 (KRW)
CMP="python/price_v8/snk_vs_scrydex_jp_compare.csv"
CAT="python/catalog_gapfill/prod_cards_full_20260620.csv"
OUT="python/price_v8/scrydex_jp_ladder_anomalies.csv"

# scrydex ladder pivot (med30 KRW per tier)
lad=defaultdict(dict)
for r in csv.reader(open(LAD)):
    if len(r)<5 or not r[0].startswith("CRD_"): continue
    try: lad[r[0]][r[1]]={"med":float(r[3]),"n":int(r[4])}
    except: pass
cat={r["card_id"]:r for r in csv.DictReader(open(CAT))}
cmp={r["card_id"]:r for r in csv.DictReader(open(CMP))}
def I(x):
    try:return int(float(x))
    except:return 0

COLS=["card_id","card_name","rarity","collection_number","snkrdunk_apparel_id",
 "scrydex_raw_krw","scrydex_psa10_krw","scrydex_psa9_krw",
 "raw_to_psa10_ratio","raw_to_psa9_ratio","psa10_to_psa9_ratio","psa10_to_raw_ratio","psa9_to_raw_ratio",
 "snk_A_basis","snk_selected_A_krw","snk_A_n","scrydex_raw_to_snk_A_ratio",
 "ladder_violation","action_status","notes"]

rows=[]; from collections import Counter; vc=Counter(); ac=Counter()
for cid,t in lad.items():
    raw=t.get("RAW",{}).get("med"); p10=t.get("PSA10",{}).get("med"); p9=t.get("PSA9",{}).get("med")
    if not raw or raw<=0: continue
    viol=[]
    if p10 and p9 and p10 < p9*0.9: viol.append("GRADED_INVERSION")
    if p10 and raw > p10*1.1: viol.append("RAW_OVER_PSA10")
    if p9  and raw > p9*1.2:  viol.append("RAW_OVER_PSA9")
    if (p10 and p10/raw>=10) or (p9 and p9/raw>=5): viol.append("RAW_STALE_LOW")
    # SNK divergence (mapping 있는 카드만)
    c=cmp.get(cid); snk_krw=I(c["selected_snk_krw"]) if c else 0
    basis=c["selected_snk_basis"] if c else "NO_MAP"
    snk_n=max(I(c["snk_A_1m_points"]),I(c["snk_A_3m_points"])) if c else 0
    snk_ratio=round(raw/snk_krw,3) if snk_krw>0 else ""
    if snk_krw>0:
        if raw/snk_krw>=2: viol.append("SNK_DIVERGENCE_HIGH")
        elif raw/snk_krw<=0.5: viol.append("SNK_DIVERGENCE_LOW")
    if not viol: continue
    for v in viol: vc[v]+=1
    # action_status
    mapping_suspect = bool(c) and c.get("data_quality")=="MAPPING_REVIEW"
    if mapping_suspect: act="MAPPING_REVIEW"
    elif basis in ("A_1M","A_3M") and snk_n>=5: act="REPLACE_WITH_SNK_A"
    elif basis in ("A_1M","A_3M") and snk_n<5: act="REVIEW_SNK_THIN"
    else: act="KEEP_SCRYDEX"
    ac[act]+=1
    m=cat.get(cid,{})
    rows.append([cid,m.get("name",""),m.get("rarity_code",""),m.get("collection_number",""),
      (c["snkrdunk_apparel_id"] if c else ""),
      round(raw),round(p10) if p10 else "",round(p9) if p9 else "",
      round(raw/p10,3) if p10 else "", round(raw/p9,3) if p9 else "",
      round(p10/p9,3) if (p10 and p9) else "", round(p10/raw,2) if p10 else "", round(p9/raw,2) if p9 else "",
      basis,snk_krw or "",snk_n,snk_ratio,
      ";".join(viol),act,""])

csv.writer(open(OUT,"w",newline="")).writerows([COLS]+rows)
print(f"=== scrydex JP ladder 이상치 = {len(rows)}장 (정상 ladder PSA10>PSA9>RAW 기준) ===")
print("위반 유형별(중복가능):")
for v,n in vc.most_common(): print(f"  {v}: {n}")
print("action_status 분포:")
for a,n in ac.most_common(): print(f"  {a}: {n}")
print(f"\n→ 바로 교정후보(REPLACE_WITH_SNK_A): {ac['REPLACE_WITH_SNK_A']} · 수동검수: {ac['REVIEW_SNK_THIN']+ac['MAPPING_REVIEW']} · scrydex유지: {ac['KEEP_SCRYDEX']}")
print(f"출력: {OUT}")
