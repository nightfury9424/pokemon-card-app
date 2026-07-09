#!/usr/bin/env python3
"""SNKRDUNK listing resolver — /en/v1/trading-cards 페이지네이션으로 전 포켓몬 단일카드 인덱스.

발견: GET /en/v1/trading-cards?page=N&perPage=100 → {"tradingCards":[{id, productNumber, name, thumbnailUrl, minPrice...}]}
- 세트별 클러스터(page500=SV8a 100장). productNumber=pkmn-tcg-{SET}-{NUM} 단일 / pkmn-tcg-{SET} 는 sealed(스킵).
- per-id detail 불필요(썸네일·번호 리스팅에 있음). 희석 없음(단일만 필터). ~2,420페이지 ≈ 24분.

출력: snk_listing_index.csv (e2e가 소비) — apparel_id 등 표준 컬럼.
정중: page당 딜레이·쿨다운·429/403 정지·체크포인트(page 재개).
read-only: prod DB write 0, 가격적재 0.
"""
import argparse, csv, json, os, re, time, random, urllib.request

ROOT = "/Users/fury/pokemon-card-app"
OUT = f"{ROOT}/python/price_v8/snk_listing_index.csv"
STATE = f"{ROOT}/python/price_v8/snk_listing_state.txt"   # 마지막 완료 page
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
EP = "https://snkrdunk.com/en/v1/trading-cards?page={p}&perPage=100"
COLS = ["apparel_id","detail_url","jp_title","en_name","product_number","image_url","set","number","rarity","used_listing_count"]

ap = argparse.ArgumentParser()
ap.add_argument("--start", type=int, default=0, help="0=state에서 재개")
ap.add_argument("--max-page", type=int, default=2600)
ap.add_argument("--delay-min", type=float, default=0.3)
ap.add_argument("--delay-max", type=float, default=0.6)
ap.add_argument("--cooldown-every", type=int, default=300)
ap.add_argument("--cooldown", type=float, default=12)
ap.add_argument("--stop-empty", type=int, default=8, help="연속 빈 페이지 N회 시 종료")
ap.add_argument("--stop-errors", type=int, default=8)
args = ap.parse_args()

SINGLE = re.compile(r"^pkmn-tcg-(.+)-(\d+)$")   # set(하이픈가능)-번호

def parse_rarity(name):
    m = re.search(r"\b(SAR|MUR|SSR|UR|SR|HR|CHR|CSR|AR|RR|ACE|K|S)\b", name or "")
    return m.group(1) if m else ""

# resume
seen = set()
if os.path.exists(OUT):
    with open(OUT, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            seen.add(str(r["apparel_id"]))
start = args.start
if start == 0 and os.path.exists(STATE):
    start = int(open(STATE).read().strip() or 0) + 1
start = max(1, start)
print(f"listing resolver 시작 page={start} · 기존 인덱스 {len(seen)}장")

new = os.path.exists(OUT)
fcsv = open(OUT, "a", encoding="utf-8", newline="")
w = csv.DictWriter(fcsv, fieldnames=COLS)
if not new:
    w.writeheader()

def fetch(p):
    req = urllib.request.Request(EP.format(p=p), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)

empty = 0; err = 0; pages = 0; hit = 0
p = start
try:
    while p <= args.max_page:
        try:
            d = fetch(p); err = 0
        except urllib.error.HTTPError as e:
            if e.code in (429, 403):
                err += 1; print(f"  page {p}: HTTP {e.code} (streak {err})")
                if err >= args.stop_errors: print("★ 차단 정지"); break
                time.sleep(args.cooldown); continue
            print(f"  page {p}: HTTP {e.code}"); d = {"tradingCards": []}
        except Exception as e:
            err += 1; print(f"  page {p}: {e} (streak {err})")
            if err >= args.stop_errors: print("★ 오류 정지"); break
            time.sleep(2); continue

        tc = d.get("tradingCards", [])
        if not tc:
            empty += 1
            if empty >= args.stop_empty:
                print(f"★ 연속 빈 페이지 {empty} — 끝 도달, 종료 (page {p})"); break
        else:
            empty = 0
        for c in tc:
            pn = c.get("productNumber") or ""
            m = SINGLE.match(pn)
            if not m:
                continue  # sealed/box 스킵
            aid = str(c["id"])
            if aid in seen:
                continue
            seen.add(aid)
            name = c.get("name") or ""
            w.writerow({
                "apparel_id": aid, "detail_url": f"https://snkrdunk.com/apparels/{aid}",
                "jp_title": name, "en_name": name, "product_number": pn,
                "image_url": (c.get("thumbnailUrl") or "").split("?")[0],
                "set": m.group(1).upper(), "number": m.group(2), "rarity": parse_rarity(name),
                "used_listing_count": c.get("listingCount", ""),
            })
            hit += 1
        pages += 1
        open(STATE, "w").write(str(p))
        if pages % 25 == 0:
            fcsv.flush()
            print(f"  page {p} · 누적 단일카드 {hit} (인덱스 총 {len(seen)})")
        if pages % args.cooldown_every == 0:
            time.sleep(args.cooldown)
        time.sleep(random.uniform(args.delay_min, args.delay_max))
        p += 1
finally:
    fcsv.close()
print(f"\n완료: page {start}~{p} · 신규 단일카드 {hit} · 인덱스 총 {len(seen)} → {OUT}")
