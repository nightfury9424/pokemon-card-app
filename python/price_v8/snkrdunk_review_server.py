#!/usr/bin/env python3
"""SNKRDUNK 검수 로컬 앱 서버 — FastAPI + SQLite. 버튼 누르면 즉시 저장(실시간).

데이터: snkrdunk_registered_image_candidates.csv (스캐너가 우리 카드로 떨어뜨린 후보) + 카탈로그 메타.
판정은 SQLite(snkrdunk_review.sqlite)에 실시간 저장. CSV는 백업/전달용(/api/export).

실행: /Users/fury/miniconda3/envs/scanner_v2/bin/python python/price_v8/snkrdunk_review_server.py
접속: http://127.0.0.1:8787
"""
import csv, json, os, re, sqlite3, time, io
from collections import defaultdict
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse, FileResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

ROOT = "/Users/fury/pokemon-card-app"
DATA = f"{ROOT}/scanner/data"
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
SNK_CATALOG = os.path.expanduser("~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv")
CAND_CSV = f"{ROOT}/python/price_v8/snkrdunk_registered_image_candidates.csv"
APP_HTML = f"{ROOT}/python/price_v8/snkrdunk_review_app.html"
DB = f"{ROOT}/python/price_v8/snkrdunk_review.sqlite"
HIGH_AUTO_SCORE = 0.80   # 자동후보 = set/rar OK + 이 점수↑ + 비프로모 (프로모/저점수는 위험군으로)
LOW_SCORE = 0.80         # 이 미만 = 저점수 위험군
PROMO_RE = __import__("re").compile(r"(-P-|-P\]| P \[|プロモ|PROMO)", __import__("re").I)
def card_is_promo(ref, rarity, best):
    # ref의 "p_ja-" 광범위 매칭 제거(swsh10p/sv2p 같은 일반 P세트가 다 걸렸음).
    # 진짜 위험군 = rarity PR(판초류) 또는 SNK 실제 프로모 마커(プロモ/ P [/-P-/PROMO).
    if (rarity or "") == "PR": return True
    if PROMO_RE.search(((best or {}).get("product_number") or "") + " " + ((best or {}).get("title") or "")): return True
    return False

# ---------- 데이터 로드 ----------
def num_int(s):
    m = re.search(r"(\d+)", str(s or "").split("/")[0].split("-")[-1]); return int(m.group(1)) if m else None

def our_img(cid):
    for s in ("_jp","_ko","_en"):
        if os.path.exists(f"{DATA}/cards/{cid}{s}.png"): return f"/static/cards/{cid}{s}.png"
    return ""

META = {}
with open(CATALOG, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        m = re.match(r"^([a-z0-9]+)_ja-\d+", (r.get("jp_scrydex_ref") or ""))
        META[r["card_id"]] = {"name": r["name"], "jp_ref": r.get("jp_scrydex_ref") or "",
                              "rarity": r["rarity_code"], "set": (m.group(1).upper() if m else ""),
                              "coll": r["collection_number"], "img": our_img(r["card_id"])}

# SNK apparel_id → EN 여부. 영문판 신호: jp_title 의 【英語版】(가장 정확) 또는 en_name 의 [EN].
# JP 소스만 쓰므로 EN 후보는 제외.
ISEN = {}
with open(SNK_CATALOG, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        ISEN[str(r["apparel_id"])] = ("英語版" in (r.get("jp_title") or "")) or ("[EN]" in (r.get("en_name") or ""))
print(f"[EN필터] EN 마킹 apparel {sum(ISEN.values())} (英語版 포함)")

CARDS = {}  # our_card_id -> {meta..., candidates:[...], high_auto:bool}
groups = defaultdict(list)
dropped_en = 0
with open(CAND_CSV, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        if ISEN.get(str(r["snkrdunk_apparel_id"])):   # EN 후보 스킵
            dropped_en += 1
            continue
        groups[r["our_card_id"]].append(r)
print(f"[EN필터] EN 후보 {dropped_en}개 제외 → JP 후보만 유지")
SKIP_RARITY = {"S", "K", "A"}  # S/K=앱 감춤(is_visible=false), A=전역숨김 → 가격매핑 제외
skipped_rarity = 0
for cid, cs in groups.items():
    if META.get(cid, {}).get("rarity", "") in SKIP_RARITY:
        skipped_rarity += 1
        continue
    cs.sort(key=lambda x: (int(x["scanner_rank"] or 9), -(float(x["scanner_score"]) if x["scanner_score"] else 0)))
    cands = []
    for x in cs:
        aid = x["snkrdunk_apparel_id"]
        cands.append({
            "apparel_id": aid, "product_number": x["snkrdunk_product_number"], "title": x["snkrdunk_title"],
            "img": f"/static/{x['snkrdunk_image_cache_path']}" if x["snkrdunk_image_cache_path"] else "",
            "detail_url": f"https://snkrdunk.com/apparels/{aid}",
            "rank": int(x["scanner_rank"] or 0), "score": float(x["scanner_score"]) if x["scanner_score"] else None,
            "set_check": x["set_number_check"], "rarity_check": x["rarity_check"],
            "match_status": x["match_status"], "top5": json.loads(x["scanner_top5_json"] or "[]"),
        })
    m = META.get(cid, {})
    best = cands[0]
    ref = m.get("jp_ref",""); rar = m.get("rarity","")
    is_promo = card_is_promo(ref, rar, best)
    num_diff = best["set_check"] == "DIFF"
    rar_diff = best["rarity_check"] == "DIFF"
    low_score = (best["score"] or 0) < LOW_SCORE
    multi = len(cands) >= 2
    high_auto = bool(best["rank"] == 1 and (best["score"] or 0) >= HIGH_AUTO_SCORE
                     and best["set_check"] == "OK" and best["rarity_check"] == "OK" and not is_promo)
    CARDS[cid] = {"our_card_id": cid, "our_name": m.get("name",""), "our_jp_ref": ref,
                  "our_rarity": rar, "our_set": m.get("set",""), "our_coll": m.get("coll",""),
                  "our_img": m.get("img",""), "candidates": cands, "high_auto": high_auto,
                  "is_promo": is_promo, "num_diff": num_diff, "rar_diff": rar_diff,
                  "low_score": low_score, "multi": multi,
                  "best_status": best["match_status"], "best_score": best["score"], "n_cand": len(cands)}
print(f"[로드] 후보카드 {len(CARDS)} · HIGH_AUTO {sum(1 for c in CARDS.values() if c['high_auto'])}")

# ---- 거절 재매칭 후보(세트+번호+이름+레어도 기반, 이미지 아님) ----
REMATCH = defaultdict(list)
_rm = os.path.join(os.path.dirname(__file__), "snkrdunk_rematch_candidates.csv")
if os.path.exists(_rm):
    for r in csv.DictReader(open(_rm, encoding="utf-8")):
        aid = r["snkrdunk_apparel_id"]
        REMATCH[r["our_card_id"]].append({
            "apparel_id": aid, "product_number": r["snkrdunk_product_number"],
            "title": r["snkrdunk_title"], "img": r["snkrdunk_image_url"],   # 풀URL(캐시X)
            "detail_url": f"https://snkrdunk.com/apparels/{aid}",
            "rank": int(r["rematch_rank"]), "score": float(r["rematch_score"]),
            "set_check": r["set_number_check"], "rarity_check": r["rarity_check"],
            "match_status": "REMATCH", "name_check": r.get("name_check","?"), "top5": [],
        })
    print(f"[재매칭] {len(REMATCH)} 거절카드에 새 후보 로드")

# ---------- SQLite ----------
def db():
    c = sqlite3.connect(DB); c.row_factory = sqlite3.Row; return c
with db() as c:
    c.execute("""CREATE TABLE IF NOT EXISTS review_decisions(
        our_card_id TEXT PRIMARY KEY, snkrdunk_apparel_id TEXT, decision TEXT, previous_status TEXT,
        scanner_score REAL, product_number TEXT, notes TEXT, created_at TEXT, updated_at TEXT)""")
    c.execute("""CREATE TABLE IF NOT EXISTS research_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT, our_card_id TEXT, current_candidate_apparel_id TEXT,
        reason TEXT, notes TEXT, status TEXT, created_at TEXT, updated_at TEXT)""")
    c.commit()

def now(): return time.strftime("%Y-%m-%d %H:%M:%S")
def get_decisions():
    with db() as c:
        return {r["our_card_id"]: dict(r) for r in c.execute("SELECT * FROM review_decisions")}
def get_research_open():
    with db() as c:
        return {r["our_card_id"] for r in c.execute("SELECT our_card_id FROM research_queue WHERE status='OPEN'")}

# 승인=통과 / 거절=맞는 후보 없음 / 삭제=이상한 카드 영구제거. (재검색/보류 폐기)
DEC2STATUS = {"APPROVED":"approved","REJECTED":"rejected","NO_VALID_CANDIDATE":"rejected","DELETED":"deleted","KO_ONLY_NO_JP":"ko_only"}
def decision_status(cid, decisions, research):
    d = decisions.get(cid)
    if d: return DEC2STATUS.get(d["decision"], "review")   # 알수없는 결정은 review로 복귀
    return None  # 미판정

def buckets_for(cid, decisions, research):
    """판정 카드는 결과 탭에만. 미판정은 ⚠️의심(번호/레어도 DIFF=오매칭·위장) vs 검수(나머지)."""
    ds = decision_status(cid, decisions, research)
    if ds: return {ds}
    c = CARDS[cid]
    return {"suspect" if (c["num_diff"] or c["rar_diff"]) else "review"}

# ---------- API ----------
app = FastAPI()
app.mount("/static", StaticFiles(directory=DATA), name="static")

@app.get("/", response_class=HTMLResponse)
def index():
    return FileResponse(APP_HTML)

@app.get("/api/progress")
def progress():
    dec, res = get_decisions(), get_research_open()
    cnt = defaultdict(int)
    for cid in CARDS:
        for t in buckets_for(cid, dec, res): cnt[t] += 1
    active = len(CARDS) - cnt.get("deleted", 0)   # 삭제된 카드는 전체에서 제외
    cnt["all"] = active; cnt["total"] = active; cnt["decided"] = len(dec)
    cnt["rematch"] = sum(1 for cid in REMATCH if cid in CARDS and decision_status(cid, dec, res) == "rejected")
    return cnt

# 위험군 우선 정렬: 저점수 먼저(가장 의심) → 번호DIFF → 프로모 → set/num
def _sort_key(cid):
    c = CARDS[cid]
    return ((c["best_score"] or 0), c["our_set"] or "", num_int(c["our_coll"]) or 0)

@app.get("/api/candidates")
def candidates(status: str = "review", offset: int = 0, limit: int = 40):
    dec, res = get_decisions(), get_research_open()
    if status == "rematch":   # 거절카드 + 재매칭 새후보(원래 이미지후보 대체)
        out = [cid for cid in REMATCH if cid in CARDS and decision_status(cid, dec, res) == "rejected"]
        out.sort(key=lambda c: -max((x["score"] for x in REMATCH[c]), default=0))   # 강한확신 먼저
        items = []
        for cid in out[offset:offset+limit]:
            c = dict(CARDS[cid]); c["candidates"] = REMATCH[cid]
            c["status"] = "rematch"; c["decision"] = dec.get(cid)
            c["best_status"] = "REMATCH"; c["best_score"] = REMATCH[cid][0]["score"]; c["n_cand"] = len(REMATCH[cid])
            items.append(c)
        return {"total": len(out), "offset": offset, "limit": limit, "items": items}
    out = [cid for cid in CARDS
           if (status == "all" and decision_status(cid, dec, res) != "deleted")
           or (status != "all" and status in buckets_for(cid, dec, res))]
    out.sort(key=_sort_key)   # 저점수(위험) 먼저
    total = len(out)
    items = []
    for cid in out[offset:offset+limit]:
        c = dict(CARDS[cid]); c["status"] = (decision_status(cid, dec, res) or "review"); c["decision"] = dec.get(cid)
        items.append(c)
    return {"total": total, "offset": offset, "limit": limit, "items": items}

@app.post("/api/decision")
async def decision(req: Request):
    b = await req.json()
    cid = b["our_card_id"]
    with db() as c:
        ex = c.execute("SELECT created_at FROM review_decisions WHERE our_card_id=?", (cid,)).fetchone()
        ca = ex["created_at"] if ex else now()
        c.execute("""INSERT INTO review_decisions(our_card_id,snkrdunk_apparel_id,decision,previous_status,
            scanner_score,product_number,notes,created_at,updated_at)
            VALUES(?,?,?,?,?,?,?,?,?)
            ON CONFLICT(our_card_id) DO UPDATE SET snkrdunk_apparel_id=excluded.snkrdunk_apparel_id,
            decision=excluded.decision,previous_status=excluded.previous_status,scanner_score=excluded.scanner_score,
            product_number=excluded.product_number,notes=excluded.notes,updated_at=excluded.updated_at""",
            (cid, b.get("snkrdunk_apparel_id"), b["decision"], b.get("previous_status"),
             b.get("scanner_score"), b.get("product_number"), b.get("notes",""), ca, now()))
        # 승인/거절 시 해당 카드의 열린 재검색 큐 닫기
        if b["decision"] in ("APPROVED","REJECTED","NO_VALID_CANDIDATE"):
            c.execute("UPDATE research_queue SET status='RESOLVED',updated_at=? WHERE our_card_id=? AND status='OPEN'",(now(),cid))
        c.commit()
    return {"ok": True, "our_card_id": cid, "decision": b["decision"]}

@app.post("/api/research")
async def research(req: Request):
    b = await req.json()
    cid = b["our_card_id"]
    with db() as c:
        # 중복 OPEN 방지
        ex = c.execute("SELECT id FROM research_queue WHERE our_card_id=? AND status='OPEN'", (cid,)).fetchone()
        if not ex:
            c.execute("""INSERT INTO research_queue(our_card_id,current_candidate_apparel_id,reason,notes,status,created_at,updated_at)
                VALUES(?,?,?,?,'OPEN',?,?)""",
                (cid, b.get("current_candidate_apparel_id"), b.get("reason","BAD_CANDIDATE_OR_NEED_MORE"),
                 b.get("notes",""), now(), now()))
        # 재검색이면 기존 결정 제거(review로 복귀 대신 research 상태)
        c.execute("DELETE FROM review_decisions WHERE our_card_id=?", (cid,))
        c.commit()
    return {"ok": True, "our_card_id": cid, "status": "research"}

@app.post("/api/bulk_approve_high_auto")
def bulk_approve():
    dec, res = get_decisions(), get_research_open()
    n = 0
    with db() as c:
        for cid, card in CARDS.items():
            if not card["high_auto"]: continue
            if cid in dec or cid in res: continue   # 이미 판정/재검색이면 건드리지 않음
            best = card["candidates"][0]
            c.execute("""INSERT INTO review_decisions(our_card_id,snkrdunk_apparel_id,decision,previous_status,
                scanner_score,product_number,notes,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)
                ON CONFLICT(our_card_id) DO NOTHING""",
                (cid, best["apparel_id"], "APPROVED", best["match_status"], best["score"],
                 best["product_number"], "HIGH_AUTO_BULK", now(), now()))
            n += 1
        c.commit()
    return {"ok": True, "approved": n}

@app.get("/api/export/decisions.csv", response_class=PlainTextResponse)
def export_decisions():
    buf = io.StringIO(); w = csv.writer(buf)
    w.writerow(["our_card_id","snkrdunk_apparel_id","decision","previous_status","scanner_score","product_number","notes","updated_at"])
    with db() as c:
        for r in c.execute("SELECT * FROM review_decisions ORDER BY updated_at DESC"):
            w.writerow([r["our_card_id"],r["snkrdunk_apparel_id"],r["decision"],r["previous_status"],
                        r["scanner_score"],r["product_number"],r["notes"],r["updated_at"]])
    return buf.getvalue()

@app.get("/api/export/research_queue.csv", response_class=PlainTextResponse)
def export_research():
    buf = io.StringIO(); w = csv.writer(buf)
    w.writerow(["id","our_card_id","current_candidate_apparel_id","reason","notes","status","updated_at"])
    with db() as c:
        for r in c.execute("SELECT * FROM research_queue ORDER BY updated_at DESC"):
            w.writerow([r["id"],r["our_card_id"],r["current_candidate_apparel_id"],r["reason"],r["notes"],r["status"],r["updated_at"]])
    return buf.getvalue()

if __name__ == "__main__":
    print("접속: http://127.0.0.1:8787")
    uvicorn.run(app, host="127.0.0.1", port=8787, log_level="warning")
