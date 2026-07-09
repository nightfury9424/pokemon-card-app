#!/usr/bin/env python3
"""SNKRDUNK 세트→apparel-id 범위 맵 — coarse 샘플러.

사이트맵 전체 id를 N개마다 1개씩 샘플 → /v1/apparels/{id} 해석 → 포켓몬 싱글의 set→id 분포 기록.
목적: 우리 148세트 각각이 SNKRDUNK id 공간 어디(min~max)에 몰려있는지 알아내 dense 타깃 크롤 윈도 결정.
(id 윈도엔 여러 프랜차이즈/세트 혼재라 '우리 세트의 범위'를 데이터로 찾아야 함.)

출력: snk_set_id_ranges.csv (set, samples, min_id, max_id, sample_ids)
정중 크롤: 딜레이/쿨다운/429·403 정지. read-only.
"""
import argparse, csv, json, os, re, time, random, urllib.request
from collections import defaultdict

ROOT = "/Users/fury/pokemon-card-app"
OUT = f"{ROOT}/python/price_v8/snk_set_id_ranges.csv"
DONE = f"{ROOT}/python/price_v8/snk_rangemap_done.txt"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
DETAIL = "https://snkrdunk.com/v1/apparels/{aid}"

ap = argparse.ArgumentParser()
ap.add_argument("--ids-file", default=f"{ROOT}/scratchpad_snk/all_sitemap_ids.txt")
ap.add_argument("--every", type=int, default=40, help="N개마다 1개 샘플")
ap.add_argument("--delay-min", type=float, default=0.3)
ap.add_argument("--delay-max", type=float, default=0.6)
ap.add_argument("--cooldown-every", type=int, default=400)
ap.add_argument("--cooldown", type=float, default=12)
ap.add_argument("--stop-errors", type=int, default=8)
args = ap.parse_args()

def is_pokemon_single(d):
    if not d or not d.get("apparelInfo", {}).get("isTradingCard"): return False
    if "trading-card-single" not in [c.get("name") for c in d.get("categories", [])]: return False
    if "pokemon" not in [b.get("id") for b in d.get("brands", [])]: return False
    return (d.get("productNumber", "") or "").startswith("pkmn-tcg-")

def set_of(d):
    m = re.search(r"\[(\w+)\s+[\d/]+\]", d.get("localizedName", "") or d.get("name", ""))
    if m: return m.group(1)
    pn = d.get("productNumber", "")  # pkmn-tcg-M3-112 → M3
    mm = re.match(r"pkmn-tcg-([A-Za-z0-9]+)-", pn)
    return mm.group(1).upper() if mm else "?"

done = set()
if os.path.exists(DONE):
    done = {int(x) for x in open(DONE).read().split() if x.strip().isdigit()}

ids = sorted({int(x) for x in open(args.ids_file).read().split() if x.strip().isdigit()})
sample = [x for i, x in enumerate(ids) if i % args.every == 0 and x not in done]
print(f"전체 {len(ids)} · 샘플(1/{args.every}) {len(sample)} (done {len(done)} 제외)")

ranges = defaultdict(list)
if os.path.exists(OUT):
    for r in csv.DictReader(open(OUT)):
        ranges[r["set"]] = [int(x) for x in r["sample_ids"].split() if x]

fdone = open(DONE, "a")
err = 0; n = 0
try:
    for aid in sample:
        n += 1
        try:
            req = urllib.request.Request(DETAIL.format(aid=aid), headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=20) as r:
                d = json.load(r)
            err = 0
        except urllib.error.HTTPError as e:
            if e.code in (429, 403):
                err += 1
                if err >= args.stop_errors: print("★ 차단 정지"); break
                time.sleep(args.cooldown); continue
            d = None
        except Exception:
            err += 1
            if err >= args.stop_errors: print("★ 오류 정지"); break
            time.sleep(2); continue
        if d and is_pokemon_single(d):
            ranges[set_of(d)].append(int(aid))
        fdone.write(f"{aid}\n")
        if n % 100 == 0:
            fdone.flush()
            print(f"  {n}/{len(sample)} · 세트 {len(ranges)}")
            # 중간 저장
            with open(OUT, "w", newline="") as f:
                w = csv.writer(f); w.writerow(["set","samples","min_id","max_id","sample_ids"])
                for s, xs in sorted(ranges.items()):
                    w.writerow([s, len(xs), min(xs), max(xs), " ".join(map(str, sorted(xs)))])
        if n % args.cooldown_every == 0:
            time.sleep(args.cooldown)
        time.sleep(random.uniform(args.delay_min, args.delay_max))
finally:
    fdone.close()
    with open(OUT, "w", newline="") as f:
        w = csv.writer(f); w.writerow(["set","samples","min_id","max_id","sample_ids"])
        for s, xs in sorted(ranges.items()):
            w.writerow([s, len(xs), min(xs), max(xs), " ".join(map(str, sorted(xs)))])
print(f"\n완료: {n} 샘플 · 포켓몬 세트 {len(ranges)}개 → {OUT}")
