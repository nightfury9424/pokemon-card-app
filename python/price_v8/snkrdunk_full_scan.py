#!/usr/bin/env python3
"""SNKRDUNK 41,610 전체 이미지를 우리 스캐너 identify 기능으로 판별.

방향(정공법): SNK 41,610 catalog의 image_url 이미지를 받아 → 우리 스캐너 /identify_path 에 질의 →
top1/top5 가 우리 등록 카드(card_id)로 떨어지는지 본다. (인덱스에 추가 X, 기존 인덱스에 질의 O)
set/number/rarity 선필터 안 함 — 스캐너가 먼저 후보를 뽑는다. (세트코드 alias 우회)

병렬 다운로드(CDN webp→png) + 순차 identify(0.05s/장). 체크포인트=JSONL append, 재개 가능.
출력 결과: snk_scan_results.jsonl (apparel_id, img, top1, top5, note) — 후속 build_review 가 소비.
read-only: 새 크롤 0(기존 CSV image_url만), prod write 0, 가격적재 0.
"""
import argparse, csv, json, os, time, urllib.request, urllib.parse, io
from concurrent.futures import ThreadPoolExecutor, as_completed
from PIL import Image

ROOT = "/Users/fury/pokemon-card-app"
BIG = os.path.expanduser("~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv")
IMG_DIR = f"{ROOT}/scanner/data/snk_images"
IMG_REL = "snk_images"
RESULTS = f"{ROOT}/python/price_v8/snk_scan_results.jsonl"
OLD_CACHE = f"{ROOT}/python/price_v8/snk_scan_cache.json"   # 기존 926건 마이그레이션
FETCHFAIL = f"{ROOT}/python/price_v8/snk_fetch_failed.txt"
SCANNER = "http://localhost:8082/identify_path"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
os.makedirs(IMG_DIR, exist_ok=True)

ap = argparse.ArgumentParser()
ap.add_argument("--catalog", default=BIG)
ap.add_argument("--dl-workers", type=int, default=16)
ap.add_argument("--limit", type=int, default=0, help=">0이면 앞 N개만(테스트)")
args = ap.parse_args()

# 카탈로그
apparels = []
with open(args.catalog, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        if (r.get("image_url") or "").startswith("http"):
            apparels.append({"aid": str(r["apparel_id"]), "url": r["image_url"]})
if args.limit:
    apparels = apparels[:args.limit]
print(f"[catalog] image_url 보유 apparel {len(apparels)}")

# 완료 집합 (JSONL + 기존 json 마이그레이션)
done = set()
if os.path.exists(RESULTS):
    with open(RESULTS, encoding="utf-8") as f:
        for line in f:
            try: done.add(json.loads(line)["aid"])
            except Exception: pass
migrated = 0
if os.path.exists(OLD_CACHE):
    old = json.load(open(OLD_CACHE))
    with open(RESULTS, "a", encoding="utf-8") as out:
        for aid, v in old.items():
            if str(aid) in done: continue
            t1 = v.get("top1") or {}
            rec = {"aid": str(aid), "img": v.get("img"),
                   "top1": ({"id": t1.get("id"), "name": t1.get("name"), "rarity": t1.get("rarity"),
                             "ref": t1.get("ref"), "score": t1.get("score")} if t1 else {}),
                   "top5": v.get("top5") or [], "note": v.get("note") or ""}
            out.write(json.dumps(rec, ensure_ascii=False) + "\n")
            done.add(str(aid)); migrated += 1
print(f"[resume] 완료 {len(done)} (기존캐시 마이그 {migrated})")

todo = [a for a in apparels if a["aid"] not in done]
print(f"[todo] {len(todo)} 처리 예정")

# ── 병렬 다운로드(webp→png) ──
def dl(a):
    aid, url = a["aid"], a["url"]
    png = f"{IMG_DIR}/{aid}.png"
    if os.path.exists(png) and os.path.getsize(png) > 800:
        return aid, png
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        data = urllib.request.urlopen(req, timeout=25).read()
        Image.open(io.BytesIO(data)).convert("RGB").save(png, "PNG")
        return aid, png
    except Exception as e:
        return aid, None

# ── identify 질의 ──
def scan(rel):
    try:
        with urllib.request.urlopen(f"{SCANNER}?path={urllib.parse.quote(rel)}", timeout=30) as r:
            d = json.load(r)
    except Exception as e:
        return None, str(e)[:40]
    st = d.get("status")
    if st in ("success", "low_confidence") and (d.get("data") or {}).get("topResult"):
        return d["data"], (st if st == "low_confidence" else "ok")
    return None, st or "scan_err"

fails = []
fout = open(RESULTS, "a", encoding="utf-8")
t0 = time.time(); n = 0; ok = 0; ferr = 0
# 다운로드를 풀로 앞서 받고, 완료되는 대로 순차 스캔
with ThreadPoolExecutor(max_workers=args.dl_workers) as pool:
    futs = {pool.submit(dl, a): a for a in todo}
    for fut in as_completed(futs):
        n += 1
        aid, png = fut.result()
        if not png:
            fails.append(aid); ferr += 1
            fout.write(json.dumps({"aid": aid, "img": None, "top1": {}, "top5": [], "note": "IMAGE_FETCH_FAILED"}, ensure_ascii=False) + "\n")
        else:
            rel = f"{IMG_REL}/{aid}.png"
            data, note = scan(rel)
            top1, top5 = {}, []
            if data:
                tr = data["topResult"]
                top1 = {"id": tr["cardId"], "name": tr["name"], "rarity": tr.get("rarityCode", ""),
                        "ref": tr.get("scrydexRef", ""), "score": round(float(tr["score"]), 4)}
                for c in data.get("candidates", [])[:5]:
                    top5.append({"cardId": c["cardId"], "name": c["name"], "rarity": c.get("rarityCode", ""),
                                 "ref": c.get("scrydexRef", ""), "score": round(float(c["score"]), 4)})
                ok += 1
            fout.write(json.dumps({"aid": aid, "img": rel, "top1": top1, "top5": top5, "note": note}, ensure_ascii=False) + "\n")
        if n % 500 == 0:
            fout.flush()
            r = n / (time.time() - t0)
            print(f"  {n}/{len(todo)} · ok {ok} · fetchfail {ferr} · {r:.1f}/s · ETA {(len(todo)-n)/max(r,0.1)/60:.0f}분", flush=True)
fout.close()
if fails:
    open(FETCHFAIL, "a").write("\n".join(fails) + "\n")
print(f"\n완료: {n} 처리 · scan ok {ok} · fetchfail {ferr} · 총 {time.time()-t0:.0f}초 → {RESULTS}")
