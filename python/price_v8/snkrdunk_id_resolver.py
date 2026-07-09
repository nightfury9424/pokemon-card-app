#!/usr/bin/env python3
"""SNKRDUNK ID resolver — 단일카드 사이트맵 id 를 /v1/apparels/{id} 로 해석해
포켓몬 싱글만 추려 (apparel_id, product_number, set, number, rarity, image_url ...) 인덱스 구축.

robots: Disallow /en/v1/* 만 → /v1/apparels/{id} 는 허용. 사이트맵 공식제공. 정중 크롤(딜레이/쿨다운/429·403 정지).
출력 포맷 = snkrdunk_apparel_catalog_scanned.csv 와 동일컬럼 → 그대로 snkrdunk_ourcard_e2e.py 가 소비.

사용:
  python snkrdunk_id_resolver.py --ids-file scratchpad_snk/all_sitemap_ids.txt --min 740000 --max 760000
  python snkrdunk_id_resolver.py --resume        # 체크포인트 이어서
read-only: prod DB write 0, 가격적재 0.
"""
import argparse, csv, json, os, re, time, random, urllib.request, sys

OUT = "/Users/fury/pokemon-card-app/python/price_v8/snk_pokemon_index.csv"
DONE = "/Users/fury/pokemon-card-app/python/price_v8/snk_resolver_done.txt"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
DETAIL = "https://snkrdunk.com/v1/apparels/{aid}"
COLS = ["apparel_id","detail_url","jp_title","en_name","product_number","image_url","set","number","rarity","used_listing_count"]

ap = argparse.ArgumentParser()
ap.add_argument("--ids-file", default="/Users/fury/pokemon-card-app/scratchpad_snk/all_sitemap_ids.txt")
ap.add_argument("--min", type=int, default=0)
ap.add_argument("--max", type=int, default=10**9)
ap.add_argument("--delay-min", type=float, default=0.35)
ap.add_argument("--delay-max", type=float, default=0.8)
ap.add_argument("--cooldown-every", type=int, default=250)
ap.add_argument("--cooldown", type=float, default=20)
ap.add_argument("--stop-errors", type=int, default=8, help="연속 429/403/네트워크 오류 N회 시 정지")
args = ap.parse_args()

def parse_title(loc):
    m = re.search(r"\[(\w+)\s+([\d/]+)\]", loc or "")
    setc, num = (m.group(1), m.group(2)) if m else ("", "")
    head = loc[:m.start()].strip() if m else (loc or "")
    rm = re.search(r"\b(SAR|MUR|SSR|UR|SR|HR|CHR|CSR|AR|RR|K|S)\b", head)
    rar = rm.group(1) if rm else ""
    name = head[:rm.start()].strip() if rm else head
    return name, setc, num, rar

def is_pokemon_single(d):
    if not d or not d.get("apparelInfo", {}).get("isTradingCard"):
        return False
    if "trading-card-single" not in [c.get("name") for c in d.get("categories", [])]:
        return False
    if "pokemon" not in [b.get("id") for b in d.get("brands", [])]:
        return False
    if not (d.get("productNumber", "") or "").startswith("pkmn-tcg-"):
        return False
    img = d.get("primaryMedia", {}).get("imageUrl", "")
    return bool(img) and "uploads/media/" not in img

def fetch(aid):
    req = urllib.request.Request(DETAIL.format(aid=aid), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r), r.status

# 이미 처리한 id (resume)
done = set()
if os.path.exists(DONE):
    done = {int(x) for x in open(DONE).read().split() if x.strip().isdigit()}

ids = [int(x) for x in open(args.ids_file).read().split() if x.strip().isdigit()]
ids = [x for x in ids if args.min <= x <= args.max and x not in done]
print(f"대상 id: {len(ids)} (범위 {args.min}~{args.max}, 이미완료 {len(done)} 제외)")

new = os.path.exists(OUT)
fcsv = open(OUT, "a", encoding="utf-8", newline="")
w = csv.DictWriter(fcsv, fieldnames=COLS)
if not new:
    w.writeheader()
fdone = open(DONE, "a")

hit = 0; err_streak = 0; n = 0
try:
    for aid in ids:
        n += 1
        try:
            d, st = fetch(aid)
            err_streak = 0
        except urllib.error.HTTPError as e:
            if e.code in (429, 403):
                err_streak += 1
                print(f"  {aid}: HTTP {e.code} (streak {err_streak})")
                if err_streak >= args.stop_errors:
                    print("★ 연속 차단 — 정중 정지."); break
                time.sleep(args.cooldown); continue
            d = None  # 404 등은 그냥 skip
        except Exception as e:
            err_streak += 1
            print(f"  {aid}: {e} (streak {err_streak})")
            if err_streak >= args.stop_errors:
                print("★ 연속 오류 — 정지."); break
            time.sleep(2); continue

        if d and is_pokemon_single(d):
            loc = d.get("localizedName", "") or d.get("name", "")
            name, setc, num, rar = parse_title(loc)
            w.writerow({
                "apparel_id": d["id"], "detail_url": f"https://snkrdunk.com/apparels/{d['id']}",
                "jp_title": loc, "en_name": d.get("name", ""), "product_number": d.get("productNumber", ""),
                "image_url": d.get("primaryMedia", {}).get("imageUrl", ""),
                "set": setc, "number": num, "rarity": rar, "used_listing_count": "",
            })
            hit += 1
        fdone.write(f"{aid}\n")
        if n % 100 == 0:
            fcsv.flush(); fdone.flush()
            print(f"  진행 {n}/{len(ids)} · 포켓몬 hit {hit}")
        if n % args.cooldown_every == 0:
            time.sleep(args.cooldown)
        time.sleep(random.uniform(args.delay_min, args.delay_max))
finally:
    fcsv.close(); fdone.close()
print(f"\n완료: {n} 처리 · 포켓몬 싱글 {hit}건 → {OUT}")
