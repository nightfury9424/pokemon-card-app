#!/usr/bin/env python3
"""확정매핑 전수 SNK sales-chart pull = A(18)/PSA10(22)/PSA9(23) 1m+3m + detail.
all(-1) 미수집. usedMinPrice=보조 호가. 재개가능(이미 한 card_id 스킵)·증분 flush.
prod write 0 · 가격 반영 0 — 분석 데이터만 적재."""
import csv, json, urllib.request, time, statistics, os, threading
from concurrent.futures import ThreadPoolExecutor

IN = "python/price_v8/snkrdunk_working_mapping.csv"
OUT = "python/price_v8/snk_price_full.csv"
B = "https://snkrdunk.com/v1/apparels/{}"
COLS = ["card_id","card_name","snkrdunk_apparel_id","usedMinPrice","usedListingCount",
        "A1m_n","A1m_med","A1m_latest","A3m_n","A3m_med","A3m_latest",
        "PSA10_1m_n","PSA10_1m_med","PSA10_3m_n","PSA10_3m_med",
        "PSA9_1m_n","PSA9_1m_med","PSA9_3m_n","PSA9_3m_med","data_quality"]

def fetch(url, retry=1):
    for i in range(retry+1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent":"Mozilla/5.0","Accept":"application/json"})
            return json.load(urllib.request.urlopen(req, timeout=12))
        except urllib.error.HTTPError as e:
            if e.code == 429: time.sleep(3); continue
            return None
        except Exception:
            if i < retry: time.sleep(0.5); continue
            return None
    return None

def pts(d): return [p[1] for p in (d.get("points") or []) if isinstance(p,list) and len(p)>=2 and p[1]] if d else []
def med(xs): return int(statistics.median(xs)) if xs else 0
def last(xs): return xs[-1] if xs else 0
def chart(aid,rng,opt): return pts(fetch(B.format(aid)+f"/sales-chart/used?range={rng}&salesChartOptionId={opt}"))

def dq(a1,a3,p10,p9):
    if a1: return "A_1M_OK"
    if a3: return "A_3M_FB"
    if p10 or p9: return "PSA_ONLY"
    return "A_NO_PTS"

rows = list(csv.DictReader(open(IN, encoding="utf-8")))
done = set()
if os.path.exists(OUT):
    done = {r["card_id"] for r in csv.DictReader(open(OUT, encoding="utf-8"))}
todo = [r for r in rows if r["our_card_id"] not in done]
print(f"[pull] 전체 {len(rows)} · 완료 {len(done)} · 남음 {len(todo)}", flush=True)

lock = threading.Lock()
f = open(OUT, "a", newline="", encoding="utf-8")
w = csv.writer(f)
if not done: w.writerow(COLS)
cnt = [0]

def work(r):
    aid = r["snkrdunk_apparel_id"]; cid = r["our_card_id"]
    det = fetch(B.format(aid)) or {}
    a1=chart(aid,"oneMonth",18); a3=chart(aid,"threeMonths",18)
    p10_1=chart(aid,"oneMonth",22); p10_3=chart(aid,"threeMonths",22)
    p9_1=chart(aid,"oneMonth",23); p9_3=chart(aid,"threeMonths",23)
    row=[cid, r["our_name"], aid, det.get("usedMinPrice",0), det.get("usedListingCount",0),
         len(a1),med(a1),last(a1), len(a3),med(a3),last(a3),
         len(p10_1),med(p10_1), len(p10_3),med(p10_3),
         len(p9_1),med(p9_1), len(p9_3),med(p9_3),
         dq(a1,a3,p10_3 or p10_1,p9_3 or p9_1)]
    with lock:
        w.writerow(row); f.flush(); cnt[0]+=1
        if cnt[0] % 50 == 0: print(f"  {cnt[0]}/{len(todo)} ...", flush=True)

with ThreadPoolExecutor(max_workers=5) as ex:
    list(ex.map(work, todo))
f.close()
print(f"[pull] 완료 — {OUT}", flush=True)
