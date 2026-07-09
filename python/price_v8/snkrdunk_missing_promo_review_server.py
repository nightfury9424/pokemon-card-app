#!/usr/bin/env python3
"""우리 DB에 없는 프로모 '추가 후보' 검수 서버 — FastAPI + SQLite (:8788).

snkrdunk_missing_promo_candidates.csv 의 후보를 SNK 이미지 보며 추가/스킵/보류/재검색.
추가 확정분만 나중에 catalog_import payload 로. prod DB write 0.
SNK 매핑 검수(:8787)와 독립. 실행: python snkrdunk_missing_promo_review_server.py → http://127.0.0.1:8788
"""
import csv, os, re, sqlite3, time, io
from collections import defaultdict
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, PlainTextResponse, FileResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

ROOT = "/Users/fury/pokemon-card-app"
DATA = f"{ROOT}/scanner/data"
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
CAND = f"{ROOT}/python/price_v8/snkrdunk_missing_promo_candidates.csv"
APP = f"{ROOT}/python/price_v8/snkrdunk_missing_promo_review.html"
DB = f"{ROOT}/python/price_v8/snkrdunk_missing_promo_review.sqlite"

def norm(s): return re.sub(r"[^A-Za-z0-9]", "", s or "").upper()

# 일본 독점/지역/이벤트/잡지 프로모 = KO 미발매 → 추가대상 아님(별도 분류)
JP_EXCL = re.compile(
    r"ポケモンセンター|ポケセン|トウホク|フクオカ|ヒロシマ|ヨコハマ|キョウト|サッポロ|オオサカ|ナゴヤ|センダイ|"
    r"カナザワ|シブヤ|イケブクロ|トウキョー|キョウハン|沖縄|オキナワ|"
    r"抽選|当選|当たり|大会|優勝|チャンピオン|参加賞|参加|入賞|ジムイベント|バトロコ|"
    r"コロコロ|月刊|付録|雑誌|記念|イベント|キャンペーン|ナガバ|NAGABA|"
    r"スペシャルBOX|スペシャルセット|サン&ムーン スターターセット|購入特典|フェスタ|"
    r"YU\s?NAGABA|切手|郵便|ローソン|セブン|アニメ|映画|劇場")
def exclusivity(title):
    return "JP_EXCLUSIVE" if JP_EXCL.search(title or "") else "GENERAL"
def our_img(cid):
    for s in ("_jp","_ko","_en"):
        if os.path.exists(f"{DATA}/cards/{cid}{s}.png"): return f"/static/cards/{cid}{s}.png"
    return ""

# 우리 DB: (set_norm, num) -> 카드 (인접 변형 표시용)
ourkey = {}
for r in csv.DictReader(open(CATALOG, encoding="utf-8")):
    m = re.match(r"^([a-z0-9]+)_ja-(\d+)", (r.get("jp_scrydex_ref") or ""))
    if m:
        ourkey[(norm(m.group(1)), int(m.group(2)))] = {"card_id": r["card_id"], "name": r["name"],
                                                        "rarity": r["rarity_code"], "img": our_img(r["card_id"])}

# 후보 로드
ITEMS = {}   # product_number -> item
by_set = defaultdict(list)
for r in csv.DictReader(open(CAND, encoding="utf-8")):
    pn = r["snkrdunk_product_number"]
    num = int(r["number"]) if (r.get("number") or "").isdigit() else None
    try: lc = int(r.get("used_listing_count") or 0)
    except: lc = 0
    aid = r["snkrdunk_apparel_id"]
    it = {"pn": pn, "set_norm": r["set_norm"], "number": num, "rarity": r["rarity"],
          "title": r["snkrdunk_title"], "lc": lc, "apparel_id": aid, "excl": exclusivity(r["snkrdunk_title"]),
          "img": f"/static/snk_images/{aid}.png", "detail_url": f"https://snkrdunk.com/apparels/{aid}",
          "fm_id": r.get("falsematch_our_card_id",""), "fm_name": r.get("falsematch_our_name",""),
          "fm_score": r.get("falsematch_score",""), "fm_img": our_img(r.get("falsematch_our_card_id","")),
          "action_hint": r.get("action","")}
    ITEMS[pn] = it
    if num is not None: by_set[it["set_norm"]].append(it)
# 인접 변형(같은 set, 번호 ±4) — 보유/누락 표시
for it in ITEMS.values():
    near = []
    if it["number"] is not None:
        for x in sorted(by_set[it["set_norm"]], key=lambda y: y["number"]):
            if x["pn"] == it["pn"]: continue
            if abs(x["number"] - it["number"]) <= 4:
                near.append({"num": x["number"], "img": x["img"], "title": x["title"][:18], "in_db": False})
        for d in range(-4, 5):
            k = (it["set_norm"], it["number"] + d)
            if d != 0 and k in ourkey:
                o = ourkey[k]; near.append({"num": it["number"]+d, "img": o["img"], "title": o["name"][:18], "in_db": True})
        near.sort(key=lambda n: n["num"])
    it["near"] = near[:10]
print(f"[로드] 추가후보 {len(ITEMS)} (lc>0 {sum(1 for i in ITEMS.values() if i['lc']>0)})")

def db():
    c = sqlite3.connect(DB); c.row_factory = sqlite3.Row; return c
with db() as c:
    c.execute("""CREATE TABLE IF NOT EXISTS promo_add_decisions(
        product_number TEXT PRIMARY KEY, apparel_id TEXT, decision TEXT, listing_count INTEGER,
        set_norm TEXT, number INTEGER, title TEXT, notes TEXT, created_at TEXT, updated_at TEXT)"""); c.commit()
def now(): return time.strftime("%Y-%m-%d %H:%M:%S")
def get_dec():
    with db() as c: return {r["product_number"]: dict(r) for r in c.execute("SELECT * FROM promo_add_decisions")}

DEC2T = {"ADD":"added","SKIP":"skipped","HOLD":"hold","RESEARCH":"research"}

app = FastAPI()
app.mount("/static", StaticFiles(directory=DATA), name="static")

@app.get("/", response_class=HTMLResponse)
def index(): return FileResponse(APP)

def item_status(it, d):
    if d: return DEC2T.get(d["decision"], "general_lc")
    if it["excl"] == "JP_EXCLUSIVE": return "exclusive"     # 일본 독점/지역/이벤트 → 별도
    return "general_lc" if it["lc"] > 0 else "general_zero"

@app.get("/api/progress")
def progress():
    dec = get_dec(); cnt = defaultdict(int)
    for pn, it in ITEMS.items():
        cnt[item_status(it, dec.get(pn))] += 1
    cnt["all"] = len(ITEMS)
    return cnt

@app.get("/api/items")
def items(status: str = "general_lc", offset: int = 0, limit: int = 40):
    dec = get_dec(); out = []
    for pn, it in ITEMS.items():
        st = item_status(it, dec.get(pn))
        if status == "all" or st == status:
            out.append((pn, st, dec.get(pn)))
    out.sort(key=lambda t: -ITEMS[t[0]]["lc"])   # 거래량 높은 순
    total = len(out); res = []
    for pn, st, d in out[offset:offset+limit]:
        c = dict(ITEMS[pn]); c["status"] = st; c["decision"] = d
        res.append(c)
    return {"total": total, "offset": offset, "limit": limit, "items": res}

@app.post("/api/decision")
async def decision(req: Request):
    b = await req.json(); pn = b["product_number"]; it = ITEMS.get(pn, {})
    with db() as c:
        ex = c.execute("SELECT created_at FROM promo_add_decisions WHERE product_number=?", (pn,)).fetchone()
        ca = ex["created_at"] if ex else now()
        c.execute("""INSERT INTO promo_add_decisions(product_number,apparel_id,decision,listing_count,set_norm,number,title,notes,created_at,updated_at)
            VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(product_number) DO UPDATE SET decision=excluded.decision,notes=excluded.notes,updated_at=excluded.updated_at""",
            (pn, it.get("apparel_id"), b["decision"], it.get("lc"), it.get("set_norm"), it.get("number"), it.get("title"), b.get("notes",""), ca, now()))
        c.commit()
    return {"ok": True, "product_number": pn, "decision": b["decision"]}

@app.get("/api/export/added.csv", response_class=PlainTextResponse)
def export_added():
    buf = io.StringIO(); w = csv.writer(buf)
    w.writerow(["product_number","apparel_id","set_norm","number","title","listing_count","decision","updated_at"])
    with db() as c:
        for r in c.execute("SELECT * FROM promo_add_decisions WHERE decision='ADD' ORDER BY listing_count DESC"):
            w.writerow([r["product_number"],r["apparel_id"],r["set_norm"],r["number"],r["title"],r["listing_count"],r["decision"],r["updated_at"]])
    return buf.getvalue()

if __name__ == "__main__":
    print("접속: http://127.0.0.1:8788")
    uvicorn.run(app, host="127.0.0.1", port=8788, log_level="warning")
