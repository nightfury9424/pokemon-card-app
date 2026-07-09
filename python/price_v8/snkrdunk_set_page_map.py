#!/usr/bin/env python3
"""SNKRDUNK 세트→페이지 맵 — stride 샘플링으로 우리 148세트가 listing의 몇 page 구간에 있는지 탐지.

전체 listing(/en/v1/trading-cards?page&perPage=100)을 다 긁지 않고 N페이지 간격으로 샘플 →
각 page의 포켓몬 단일카드 set_code 분포 기록 → 세트별 등장 page 범위 추정 → 그 구간만 dense 타깃 크롤.

출력: snkrdunk_set_page_map.csv (set_code, sample_pages, first_seen_page, last_seen_page,
      estimated_page_min, estimated_page_max, sample_count, matched_our_card_count, is_ours, notes)
정중: page당 딜레이·쿨다운·429/403 정지·체크포인트(page 재개).
"""
import argparse, csv, json, os, re, time, random, urllib.request
from collections import defaultdict, Counter

ROOT = "/Users/fury/pokemon-card-app"
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
OUT = f"{ROOT}/python/price_v8/snkrdunk_set_page_map.csv"
RAW = f"{ROOT}/python/price_v8/snk_set_page_samples.json"   # {page: {set:count}}
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
EP = "https://snkrdunk.com/en/v1/trading-cards?page={p}&perPage=100"
SINGLE = re.compile(r"^pkmn-tcg-(.+)-(\d+)$")

ap = argparse.ArgumentParser()
ap.add_argument("--stride", type=int, default=12)
ap.add_argument("--max-page", type=int, default=2600)
ap.add_argument("--delay-min", type=float, default=0.2)
ap.add_argument("--delay-max", type=float, default=0.4)
ap.add_argument("--cooldown-every", type=int, default=120)
ap.add_argument("--cooldown", type=float, default=10)
ap.add_argument("--stop-empty", type=int, default=6)
ap.add_argument("--stop-errors", type=int, default=8)
args = ap.parse_args()

# 우리 세트별 카드수
our_set_count = Counter()
for r in csv.DictReader(open(CATALOG)):
    m = re.match(r"^([a-z0-9]+)_ja-\d+", (r.get("jp_scrydex_ref") or ""))
    if m: our_set_count[m.group(1).upper()] += 1

# resume
samples = {}
if os.path.exists(RAW):
    try: samples = {int(k): v for k, v in json.load(open(RAW)).items()}
    except Exception: samples = {}

pages = list(range(1, args.max_page + 1, args.stride))
todo = [p for p in pages if p not in samples]
print(f"샘플 대상 {len(todo)} page (stride {args.stride}, 기존 {len(samples)})")

def fetch(p):
    req = urllib.request.Request(EP.format(p=p), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=25) as r:
        return json.load(r)

empty = 0; err = 0; n = 0
try:
    for p in todo:
        n += 1
        try:
            d = fetch(p); err = 0
        except urllib.error.HTTPError as e:
            if e.code in (429, 403):
                err += 1; print(f"  page {p}: {e.code}")
                if err >= args.stop_errors: print("★ 차단 정지"); break
                time.sleep(args.cooldown); continue
            d = {"tradingCards": []}
        except Exception as e:
            err += 1; print(f"  page {p}: {e}")
            if err >= args.stop_errors: print("★ 오류 정지"); break
            time.sleep(2); continue
        tc = d.get("tradingCards", [])
        cnt = Counter()
        for c in tc:
            m = SINGLE.match(c.get("productNumber") or "")
            if m: cnt[m.group(1).upper()] += 1
        samples[p] = dict(cnt)
        if not tc:
            empty += 1
            if empty >= args.stop_empty:
                print(f"★ 빈 페이지 연속 {empty} (page {p}) — 끝 추정, 종료"); break
        else:
            empty = 0
        if n % 20 == 0:
            json.dump(samples, open(RAW, "w"))
            print(f"  {n}/{len(todo)} (page {p}) · 발견세트 {len({s for v in samples.values() for s in v})}")
        if n % args.cooldown_every == 0:
            time.sleep(args.cooldown)
        time.sleep(random.uniform(args.delay_min, args.delay_max))
finally:
    json.dump(samples, open(RAW, "w"))

# 집계: 세트 → 등장 page
set_pages = defaultdict(list)
for p, sc in samples.items():
    for s, c in sc.items():
        set_pages[s].append((p, c))
rows = []
for s, pcs in set_pages.items():
    ps = sorted(p for p, _ in pcs)
    rows.append({
        "set_code": s, "sample_pages": " ".join(map(str, ps)),
        "first_seen_page": ps[0], "last_seen_page": ps[-1],
        "estimated_page_min": max(1, ps[0] - args.stride),
        "estimated_page_max": ps[-1] + args.stride,
        "sample_count": sum(c for _, c in pcs),
        "matched_our_card_count": our_set_count.get(s, 0),
        "is_ours": "Y" if s in our_set_count else "",
        "notes": "",
    })
rows.sort(key=lambda r: (-r["matched_our_card_count"], r["first_seen_page"]))
with open(OUT, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["set_code","sample_pages","first_seen_page","last_seen_page",
        "estimated_page_min","estimated_page_max","sample_count","matched_our_card_count","is_ours","notes"])
    w.writeheader()
    for r in rows: w.writerow(r)

ours_found = [r for r in rows if r["is_ours"]]
print(f"\n샘플 {len(samples)} page · 발견세트 {len(rows)} · 우리세트 위치찾음 {len(ours_found)}/{len(our_set_count)}")
print(f"→ {OUT}")
