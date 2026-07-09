#!/usr/bin/env python3
"""148 REPLACE 후보 재필터링 → STRONG_REPLACE만 추림. 분석 전용, 대체 적용 0.
STRONG = SNK_DIVERGENCE(HIGH/LOW) + n>=5 + mapping 정상 + ¥1,000 floor 아님.
RAW_STALE_LOW-only는 graded premium라 정상 가능 → LADDER_INFO_ONLY로 강등."""
import csv
from collections import Counter
A="python/price_v8/scrydex_jp_ladder_anomalies.csv"
OUTA="python/price_v8/scrydex_jp_ladder_anomalies.csv"   # replacement_confidence 컬럼 추가해서 재기록
OUTS="python/price_v8/scrydex_jp_snk_replace_candidates_strong.csv"
FLOOR_KRW=9500   # ¥1,000 × 9.5 = SNK 최저 floor 의심

rows=list(csv.DictReader(open(A)))
def I(x):
    try:return int(float(x))
    except:return 0
def conf(r):
    v=set((r["ladder_violation"] or "").split(";"))
    div = ("SNK_DIVERGENCE_HIGH" in v) or ("SNK_DIVERGENCE_LOW" in v)
    n=I(r["snk_A_n"]); snk_krw=I(r["snk_selected_A_krw"])
    floor = snk_krw>0 and snk_krw<=FLOOR_KRW
    if r["action_status"]=="MAPPING_REVIEW": return "MAPPING_REVIEW",floor
    if div and n>=5 and not floor: return "STRONG_REPLACE",floor
    if div and (n<5 or floor): return "REVIEW_REPLACE",floor
    if v=={"RAW_STALE_LOW"}: return "LADDER_INFO_ONLY",floor
    return "KEEP",floor

cols=list(rows[0].keys())
if "replacement_confidence" not in cols: cols+=["replacement_confidence","floor_suspect"]
cc=Counter(); strong=[]
# 148 REPLACE_WITH_SNK_A 교차표
repl=[r for r in rows if r["action_status"]=="REPLACE_WITH_SNK_A"]
xt=Counter()
for r in repl:
    for v in (r["ladder_violation"] or "").split(";"): xt[v]+=1
    if (r["ladder_violation"] or "")=="RAW_STALE_LOW": xt["__RAW_STALE_LOW_ONLY"]+=1
for r in rows:
    c,floor=conf(r); r["replacement_confidence"]=c; r["floor_suspect"]="Y" if floor else ""
    cc[c]+=1
    if c=="STRONG_REPLACE": strong.append(r)
w=csv.DictWriter(open(OUTA,"w",newline=""),fieldnames=cols); w.writeheader(); w.writerows(rows)
ws=csv.DictWriter(open(OUTS,"w",newline=""),fieldnames=cols); ws.writeheader(); ws.writerows(strong)

print("=== REPLACE_WITH_SNK_A 148장 교차표 (violation 포함 수) ===")
for k in ["SNK_DIVERGENCE_HIGH","SNK_DIVERGENCE_LOW","RAW_OVER_PSA9","RAW_OVER_PSA10","GRADED_INVERSION","RAW_STALE_LOW","__RAW_STALE_LOW_ONLY"]:
    print(f"  {k}: {xt[k]}")
print(f"\n=== replacement_confidence 분포 (전체 {len(rows)} anomaly) ===")
for k in ["STRONG_REPLACE","REVIEW_REPLACE","LADDER_INFO_ONLY","MAPPING_REVIEW","KEEP"]:
    print(f"  {k}: {cc[k]}")
print(f"  floor 의심(¥1,000) 총: {sum(1 for r in rows if r['floor_suspect']=='Y')}")
print(f"\n→ STRONG_REPLACE {len(strong)}장 → {OUTS}")
print("\n=== STRONG_REPLACE TOP 30 (발산 큰 순) ===")
def sev(r):
    rt=float(r["scrydex_raw_to_snk_A_ratio"] or 1); return max(rt,1/rt) if rt>0 else 0
for r in sorted(strong,key=sev,reverse=True)[:30]:
    print(f"  {r['card_name'][:14]:14} {r['rarity']:4} raw₩{I(r['scrydex_raw_krw']):>7,} vs SNK_A₩{I(r['snk_selected_A_krw']):>7,} x{r['scrydex_raw_to_snk_A_ratio']:>5} n={r['snk_A_n']:>2} [{r['ladder_violation']}]"[:116])
