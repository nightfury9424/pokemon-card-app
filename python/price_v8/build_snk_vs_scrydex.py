#!/usr/bin/env python3
"""SNK A 시계열 vs scrydex JP 비교표. 분석 전용 — prod write 0, 가격 반영 0.
- SNK A(18) = raw JP 주력 / PSA10·PSA9 = ladder 참고 / usedMinPrice = ASK 보조
- scrydex JP = 비교/ fallback. 둘 다 KRW 환산해서 ratio.
"""
import csv, statistics
USD, JPY = 1536.48, 9.50   # prod 라이브 (price/100)
MAP="python/price_v8/snkrdunk_working_mapping.csv"     # working/high-confidence mapping
SNK="python/price_v8/snk_price_full.csv"
SCRY="python/price_v8/scrydex_jp_prod.csv"
CAT="python/catalog_gapfill/prod_cards_full_20260620.csv"
OUT="python/price_v8/snk_vs_scrydex_jp_compare.csv"

cat={r["card_id"]:r for r in csv.DictReader(open(CAT,encoding="utf-8"))}
snk={r["card_id"]:r for r in csv.DictReader(open(SNK,encoding="utf-8"))}
scry={}
for r in csv.reader(open(SCRY,encoding="utf-8")):
    if len(r)>=6 and r[0].startswith("CRD_"):
        scry[r[0]]={"latest":r[1],"cur":r[2],"med30":r[3],"n30":r[4],"date":r[5]}
mp=list(csv.DictReader(open(MAP,encoding="utf-8")))

def f(x):
    try: return float(x)
    except: return 0.0
def i(x):
    try: return int(x)
    except: return 0

COLS=["card_id","card_name","rarity","collection_number","snkrdunk_apparel_id","mapping_status",
 "scrydex_jp_latest_krw","scrydex_jp_30d_median_krw","scrydex_jp_source_date",
 "snk_A_1m_points","snk_A_1m_median_jpy","snk_A_1m_latest_jpy","snk_A_3m_points","snk_A_3m_median_jpy","snk_A_3m_latest_jpy",
 "snk_PSA10_1m_points","snk_PSA10_1m_median_jpy","snk_PSA10_3m_points","snk_PSA10_3m_median_jpy",
 "snk_PSA9_1m_points","snk_PSA9_1m_median_jpy","snk_PSA9_3m_points","snk_PSA9_3m_median_jpy",
 "usedMinPrice_jpy","usedListingCount",
 "selected_snk_raw_jpy","selected_snk_basis","selected_snk_krw",
 "ratio_scrydex_to_snk","diff_pct","data_quality","notes"]

rows=[]; ratios=[]
for m in mp:
    cid=m["our_card_id"]
    if (m.get("our_rarity") or "").upper() in ("S","A","K"): continue
    s=snk.get(cid,{}); x=scry.get(cid)
    cmeta=cat.get(cid,{})
    # scrydex → KRW
    scry_lat_krw=scry_med_krw=0; scry_date=""
    if x:
        mult=USD if x["cur"]=="USD" else JPY
        scry_lat_krw=round(f(x["latest"])*mult); scry_med_krw=round(f(x["med30"])*mult); scry_date=x["date"]
    # SNK raw 선택: A1m → A3m
    a1n,a1m=i(s.get("A1m_n")),i(s.get("A1m_med")); a3n,a3m=i(s.get("A3m_n")),i(s.get("A3m_med"))
    if a1n>0: sel_jpy,basis=a1m,"A_1M"
    elif a3n>0: sel_jpy,basis=a3m,"A_3M"
    else: sel_jpy,basis=0,"NONE"
    sel_krw=round(sel_jpy*JPY)
    dq=s.get("data_quality","") or ("SCRYDEX_ONLY" if x else "NO_DATA")
    if basis=="NONE": dq="SCRYDEX_ONLY" if x else "NO_DATA"
    elif dq=="A_1M_OK": dq="SNK_A_1M_OK"
    elif dq=="A_3M_FB": dq="SNK_A_3M_FALLBACK"
    ratio=note=""
    if sel_krw>0 and scry_med_krw>0:
        ratio=round(scry_med_krw/sel_krw,3); ratios.append(ratio)
        if ratio>=2: note="SCRYDEX_2X_HIGH"
        elif ratio<=0.5: note="SCRYDEX_HALF_LOW"
        if ratio>=3 or ratio<=0.33: dq="MAPPING_REVIEW"
    diff_pct=round((scry_med_krw-sel_krw)/sel_krw*100,1) if sel_krw>0 and scry_med_krw>0 else ""
    rows.append([cid,m["our_name"],m.get("our_rarity",""),cmeta.get("collection_number",""),m["snkrdunk_apparel_id"],"high_confidence",
      scry_lat_krw,scry_med_krw,scry_date,
      a1n,a1m,i(s.get("A1m_latest")),a3n,a3m,i(s.get("A3m_latest")),
      i(s.get("PSA10_1m_n")),i(s.get("PSA10_1m_med")),i(s.get("PSA10_3m_n")),i(s.get("PSA10_3m_med")),
      i(s.get("PSA9_1m_n")),i(s.get("PSA9_1m_med")),i(s.get("PSA9_3m_n")),i(s.get("PSA9_3m_med")),
      i(s.get("usedMinPrice")),i(s.get("usedListingCount")),
      sel_jpy,basis,sel_krw, ratio,diff_pct,dq,note])

w=csv.writer(open(OUT,"w",newline="",encoding="utf-8")); w.writerow(COLS); w.writerows(rows)

# ===== 분석 요약 =====
both=[r for r in rows if r[27]>0 and r[7]>0]   # selected_snk_krw(27)>0 and scry_med_krw(7)>0
snk_has_A=[r for r in rows if r[26]!="NONE"]    # basis(26)
scry_only=[r for r in rows if r[26]=="NONE" and r[7]>0]
no_data=[r for r in rows if r[26]=="NONE" and r[7]==0]
hi=[r for r in both if r[28]>=2]; lo=[r for r in both if r[28]<=0.5]   # ratio(28)
print(f"=== SNK A vs scrydex JP 비교 ({len(rows)} working mapping) ===")
print(f"  비교가능(둘다 값): {len(both)}")
print(f"  SNK A raw 있음: {len(snk_has_A)} · SNK A 없음: {len(rows)-len(snk_has_A)}")
print(f"  scrydex만(SNK A 없음): {len(scry_only)} · 둘다없음: {len(no_data)}")
if ratios:
    print(f"  scrydex/SNK ratio 중앙값: {statistics.median(ratios):.2f} (1=동일, >1=scrydex가 높음)")
    print(f"  평균: {statistics.mean(ratios):.2f}")
print(f"  scrydex가 SNK 2배+ 높음: {len(hi)} ({len(hi)*100//max(1,len(both))}%)")
print(f"  scrydex가 SNK 50%- 낮음: {len(lo)} ({len(lo)*100//max(1,len(both))}%)")
print("\n--- scrydex 과대(ratio 큰) TOP 15 (SNK 대체 시 가격 down) ---")
for r in sorted(both,key=lambda r:-r[28])[:15]:
    print(f"  {r[1][:16]:16} {r[2]:4} scry W{r[7]:>8,} vs SNK_A W{r[27]:>8,} = x{r[28]:.1f} [{r[31]}]")
print("\n--- scrydex 과소(ratio 작은) TOP 10 (SNK 대체 시 가격 up) ---")
for r in sorted(both,key=lambda r:r[28])[:10]:
    print(f"  {r[1][:16]:16} {r[2]:4} scry W{r[7]:>8,} vs SNK_A W{r[27]:>8,} = x{r[28]:.2f}")
print(f"\\n출력: {OUT}")
