#!/usr/bin/env python3
"""우리 DB에 없는 SNK(일판) 프로모 = 추가 대상 후보 리스트.

핵심: 프로모 세트코드가 우리(scrydex)와 SNK 표기가 달라(smp ↔ SM-P) 정규화 후 (set,num) 비교.
SNK 프로모(EN제외) 중 (정규화set, num)이 우리 DB에 없는 것 = 우리가 안 가진 프로모 → 추가 후보.
인기순(used_listing_count)으로 정렬 → 거래 많은 것부터 추가 판단.

산출: snkrdunk_missing_promo_candidates.csv  (read-only, DB write 0)
"""
import csv, json, os, re
from collections import defaultdict, Counter

ROOT = "/Users/fury/pokemon-card-app"
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
SNK = os.path.expanduser("~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv")
JSONL = f"{ROOT}/python/price_v8/snk_scan_results.jsonl"
OUT = f"{ROOT}/python/price_v8/snkrdunk_missing_promo_candidates.csv"

def norm(s): return re.sub(r"[^A-Za-z0-9]", "", s or "").upper()
PROMO_RE = re.compile(r"(-P-|-P\]| P \[|プロモ|PROMO)", re.I)

# 1) 우리 DB의 (정규화set, num) 집합 — 프로모 포함 전체
our_keys = set()
our_names = {}
for r in csv.DictReader(open(CATALOG, encoding="utf-8")):
    m = re.match(r"^([a-z0-9]+)_ja-(\d+)", (r.get("jp_scrydex_ref") or ""))
    if m:
        k = (norm(m.group(1)), int(m.group(2)))
        our_keys.add(k)
        our_names.setdefault(k, r["name"])
print(f"[우리 DB] (set,num) 키 {len(our_keys)}")

# 2) 스캔결과 top1 (그 SNK 프로모가 뭘로 잘못 떨어졌나 = 오매칭 근거)
top1 = {}
for line in open(JSONL, encoding="utf-8"):
    try: d = json.loads(line)
    except: continue
    top1[d["aid"]] = d.get("top1") or {}

# 3) SNK 프로모(EN제외) → product_number 기준 dedup, 우리 DB에 없는 것
def parse_pn(pn):
    pn2 = re.sub(r"^pkmn-tcg-", "", pn or "")
    m = re.match(r"^(.+)-(\d+)$", pn2)
    return (m.group(1), int(m.group(2))) if m else (pn2, None)

by_pn = {}
for r in csv.DictReader(open(SNK, encoding="utf-8")):
    jp = r.get("jp_title",""); en = r.get("en_name","")
    if "英語版" in jp or "[EN]" in en: continue            # EN 제외
    pn = r.get("product_number","")
    if not (PROMO_RE.search(pn + " " + jp) or " P [" in jp): continue  # 프로모만
    setc, num = parse_pn(pn)
    nset = norm(setc)
    key = (nset, num)
    try: lc = int(r.get("used_listing_count") or 0)
    except: lc = 0
    rec = by_pn.get(pn)
    if rec is None or lc > rec["lc"]:
        by_pn[pn] = {"aid": str(r["apparel_id"]), "pn": pn, "set": setc, "num": num, "nset": nset,
                     "title": jp, "rarity": r.get("rarity",""), "img": r.get("image_url",""),
                     "lc": lc, "in_db": (key in our_keys), "key": key}

missing = [v for v in by_pn.values() if v["num"] is not None and not v["in_db"]]
weird = [v for v in by_pn.values() if v["num"] is None]   # 번호 파싱불가(특수프로모)
have = [v for v in by_pn.values() if v["in_db"]]
missing.sort(key=lambda x: -x["lc"])

# CSV
COLS = ["snkrdunk_product_number","set_norm","number","rarity","snkrdunk_title","used_listing_count",
        "snkrdunk_apparel_id","snkrdunk_image_url","falsematch_our_card_id","falsematch_our_name","falsematch_score","action"]
with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=COLS); w.writeheader()
    for v in missing + weird:
        t1 = top1.get(v["aid"], {})
        fc = t1.get("id",""); fn = our_names.get((norm(re.match(r'^([a-z0-9]+)_ja',t1.get('ref','') or '_').group(1) if re.match(r'^([a-z0-9]+)_ja',t1.get('ref','') or '') else ''), None) if False else "", "")
        w.writerow({
            "snkrdunk_product_number": v["pn"], "set_norm": v["nset"], "number": (v["num"] if v["num"] is not None else ""),
            "rarity": v["rarity"], "snkrdunk_title": v["title"], "used_listing_count": v["lc"],
            "snkrdunk_apparel_id": v["aid"], "snkrdunk_image_url": v["img"],
            "falsematch_our_card_id": t1.get("id",""), "falsematch_our_name": t1.get("name",""),
            "falsematch_score": t1.get("score",""),
            "action": ("ADD_CANDIDATE" if v["num"] is not None else "SPECIAL_PROMO_REVIEW"),
        })

print(f"[CSV] {OUT}")
print("="*55)
print(f"  SNK 프로모 고유 product : {len(by_pn)}")
print(f"  우리 DB에 이미 있음     : {len(have)}")
print(f"  우리 DB에 없음(추가후보): {len(missing)}")
print(f"  번호파싱불가(특수프로모): {len(weird)}")
print(f"  추가후보 중 거래있음(lc>0): {sum(1 for v in missing if v['lc']>0)}")
print("  === 추가후보 인기 top 15 ===")
for v in missing[:15]:
    print(f"   lc{v['lc']:>4} | {v['pn']:22} | {v['title'][:42]}")
print("  === 판초 이브이 SM-P 누락분 확인 ===")
for v in sorted([x for x in by_pn.values() if x['nset']=='SMP' and x['num'] and 135<=x['num']<=146], key=lambda x:x['num']):
    print(f"   SM-P-{v['num']} {'있음' if v['in_db'] else '없음(추가)'} | {v['title'][:36]}")
