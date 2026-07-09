#!/usr/bin/env python3
"""⑤ SNK 검수 UI 서버 (로컬·dry-run). review_queue 를 사람이 approve/reject.

★ HIGH(scrydex 과대→하향, 저위험) 먼저. 버튼=approve_replace/reject_keep/hold/mapping_review.
저장 = review_queue.review_status 로컬 SQLite 업데이트만. **prod write 0 · 가격 반영 0.**

데이터:
  review_queue / snk_snapshot  ← snk_pipeline.sqlite (collector+detector 산출)
  우리 카드 이미지             ← scanner/data/cards/{cid}_jp.png (StaticFiles)
  SNK title/이미지/usedMin     ← SNK detail API (라이브, snk_detail_cache.json 캐시)
  카탈로그 메타                ← prod_cards_full_20260620.csv

실행 (scanner_v2 env):
  cd python/price_v8 && \
  /Users/fury/miniconda3/envs/scanner_v2/bin/python -m snk_pipeline.review_server
접속: http://127.0.0.1:8788
"""
import csv
import datetime
import json
import os

from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
import uvicorn

from . import config, db, snk_client

import statistics

HERE = os.path.dirname(__file__)
CARDS_DIR = os.path.join(config.ROOT, "scanner", "data", "cards")
APP_HTML = os.path.join(HERE, "review_app.html")
DETAIL_CACHE = os.path.join(HERE, "snk_detail_cache.json")
CHART_CACHE = os.path.join(HERE, "snk_chart_cache.json")
PORT = 8788

DECISION_MAP = {
    "approve_replace": "APPROVED_REPLACE_WITH_SNK",
    "reject_keep": "REJECTED_KEEP_SCRYDEX",
    "hold": "HOLD",
    "mapping_review": "MAPPING_REVIEW",
}

# ── 카탈로그 메타 (우리 이미지 경로) ──────────────────────────────
CATALOG = {}
if os.path.exists(config.CATALOG_CSV):
    with open(config.CATALOG_CSV, encoding="utf-8") as f:
        for r in csv.DictReader(f):
            CATALOG[r["card_id"]] = r


def our_img(cid):
    for suf in ("_jp", "_ko", "_en"):
        if os.path.exists(os.path.join(CARDS_DIR, f"{cid}{suf}.png")):
            return f"/static/{cid}{suf}.png"
    return ""


# ── SNK detail 캐시 (title/이미지/usedMin) ────────────────────────
def _load_cache():
    if os.path.exists(DETAIL_CACHE):
        try:
            return json.load(open(DETAIL_CACHE, encoding="utf-8"))
        except Exception:
            return {}
    return {}


_cache = _load_cache()


def snk_detail(aid):
    key = str(aid)
    if key in _cache:
        return _cache[key]
    d = snk_client.detail(aid) or {}
    out = {
        "title": d.get("name", ""),
        "product_number": d.get("productNumber", ""),
        "img": (d.get("primaryMedia") or {}).get("imageUrl", ""),
        "used_min_jpy": int(d.get("usedMinPrice", 0) or 0),
        "used_listing": int(d.get("usedListingCount", 0) or 0),
    }
    _cache[key] = out
    try:
        json.dump(_cache, open(DETAIL_CACHE, "w", encoding="utf-8"), ensure_ascii=False)
    except Exception:
        pass
    return out


def snk_psa(conn, run_id, card_id, tier):
    """snk_snapshot 의 PSA tier median KRW: 1m(n>0) 우선 else 3m."""
    rows = conn.execute(
        """SELECT range_label, points_count, price_krw FROM snk_snapshot
           WHERE run_id=? AND card_id=? AND tier=? AND basis='median'""",
        (run_id, card_id, tier)).fetchall()
    by = {r["range_label"]: (r["points_count"], r["price_krw"]) for r in rows}
    n1, k1 = by.get("1m", (0, 0))
    n3, k3 = by.get("3m", (0, 0))
    if n1 > 0:
        return k1, n1
    if n3 > 0:
        return k3, n3
    return None, 0


app = FastAPI()
app.mount("/static", StaticFiles(directory=CARDS_DIR), name="static")


@app.get("/", response_class=HTMLResponse)
def index():
    return open(APP_HTML, encoding="utf-8").read()


GRAIL_HTML = os.path.join(HERE, "grail_review.html")
GRAIL_CSV = os.path.join(HERE, "out", "grail_evidence.csv")


@app.get("/grail", response_class=HTMLResponse)
def grail_page():
    return open(GRAIL_HTML, encoding="utf-8").read()


@app.get("/api/grail")
def api_grail(evidence: str = "ALL"):
    rows = list(csv.DictReader(open(GRAIL_CSV, encoding="utf-8")))
    out = []
    for r in rows:
        if evidence != "ALL" and r["evidence_strength"] != evidence:
            continue
        r["our_img"] = our_img(r["card_id"])
        out.append(r)
    return JSONResponse({"rows": out, "total": len(rows)})


@app.get("/api/queue")
def api_queue(priority: str = "HIGH", status: str = "ALL"):
    conn = db.init()
    q = "SELECT * FROM review_queue WHERE 1=1"
    args = []
    if priority and priority != "ALL":
        q += " AND priority=?"
        args.append(priority)
    if status and status != "ALL":
        q += " AND review_status=?"
        args.append(status)
    # ★ 검거 우선순위: ①scrydex 자체 ladder 위배(RAW_OVER_*/GRADED_INVERSION = scrydex 명백 오류)
    #   ②STRONG_REPLACE ③발산 큰 순
    q += (" ORDER BY "
          " CASE WHEN ladder_violation LIKE '%RAW_OVER%' OR ladder_violation LIKE '%GRADED_INVERSION%'"
          "      THEN 0 ELSE 1 END,"
          " CASE replacement_confidence WHEN 'STRONG_REPLACE' THEN 0 ELSE 1 END,"
          " scrydex_raw_to_snk_A_ratio DESC")
    rows = conn.execute(q, args).fetchall()

    out = []
    for r in rows:
        cid, aid = r["card_id"], r["snkrdunk_apparel_id"]
        det = snk_detail(aid)
        psa10_krw, psa10_n = snk_psa(conn, r["run_id"], cid, "PSA10")
        psa9_krw, psa9_n = snk_psa(conn, r["run_id"], cid, "PSA9")
        raw, snkA = r["scrydex_raw_krw"], r["snk_A_krw"]
        prio = r["priority"]
        proposed = ("DOWN_TO_SNK_A" if prio == "HIGH"
                    else "UP_TO_SNK_A (고위험)" if prio == "LOW" else "REVIEW")
        change_pct = round((snkA - raw) / raw * 100) if raw else None
        out.append({
            "card_id": cid, "run_id": r["run_id"],
            "card_name": r["card_name"] or CATALOG.get(cid, {}).get("name", ""),
            "rarity": r["rarity"], "collection_number": r["collection_number"],
            "apparel_id": aid, "detail_url": f"https://snkrdunk.com/apparels/{aid}",
            "our_img": our_img(cid), "snk_img": det["img"],
            "snk_title": det["title"], "snk_product_number": det["product_number"],
            "scrydex_raw": raw, "scrydex_psa10": r["scrydex_psa10_krw"], "scrydex_psa9": r["scrydex_psa9_krw"],
            "snk_A": snkA, "snk_A_basis": r["snk_A_basis"], "snk_A_n": r["snk_A_n"],
            "snk_A_n_3m": r["snk_A_n_3m"],
            "snk_psa10": psa10_krw, "snk_psa10_n": psa10_n, "snk_psa9": psa9_krw, "snk_psa9_n": psa9_n,
            "used_min_jpy": det["used_min_jpy"], "used_min_krw": round(det["used_min_jpy"] * config.JPY_KRW),
            "used_listing": det["used_listing"],
            "ratio": r["scrydex_raw_to_snk_A_ratio"], "change_pct": change_pct,
            "ladder_violation": r["ladder_violation"], "action_status": r["action_status"],
            "confidence": r["replacement_confidence"], "priority": prio,
            "floor_suspect": r["floor_suspect"], "proposed_action": proposed,
            "review_status": r["review_status"], "reviewed_by": r["reviewed_by"],
            "reviewed_at": r["reviewed_at"], "review_note": r["review_note"],
        })
    counts = {}
    for r in conn.execute(
            "SELECT review_status, COUNT(*) c FROM review_queue WHERE priority=? GROUP BY review_status",
            (priority,) if priority != "ALL" else ()) if priority != "ALL" else \
            conn.execute("SELECT review_status, COUNT(*) c FROM review_queue GROUP BY review_status"):
        counts[r["review_status"]] = r["c"]
    return JSONResponse({"rows": out, "counts": counts,
                         "rate_note": f"JPY×{config.JPY_KRW} (참고환율 {config.RATE_AS_OF})"})


def _load_json(path):
    if os.path.exists(path):
        try:
            return json.load(open(path, encoding="utf-8"))
        except Exception:
            return {}
    return {}


_chart_cache = _load_json(CHART_CACHE)


def _krw(jpy):
    return round(jpy * config.JPY_KRW)


def _fmt_ts(ts_ms):
    return datetime.datetime.fromtimestamp(ts_ms / 1000).strftime("%Y-%m-%d")


@app.get("/api/chart")
def api_chart(apparel_id: int):
    """검수용 SNK sales-chart 시계열 + RAW 분포/최근거래 (라이브, 캐시). prod 무관."""
    key = str(apparel_id)
    if key in _chart_cache:
        return JSONResponse(_chart_cache[key])
    raw1 = snk_client.chart_pairs(apparel_id, "oneMonth", config.OPT_A)
    raw3 = snk_client.chart_pairs(apparel_id, "threeMonths", config.OPT_A)
    p9 = snk_client.chart_pairs(apparel_id, "threeMonths", config.OPT_PSA9)
    p10 = snk_client.chart_pairs(apparel_id, "threeMonths", config.OPT_PSA10)

    # 결정 윈도우 = 스냅샷 basis 와 동일(A_1M 우선, 빈약하면 3M)
    dec = raw1 if len(raw1) >= 5 else (raw3 or raw1)
    prices = sorted(p for _, p in dec)
    raw_stats = {}
    if prices:
        n = len(prices)
        def q(frac):
            return prices[min(n - 1, max(0, int(n * frac)))]
        recent = sorted(dec, key=lambda x: x[0], reverse=True)[:8]
        raw_stats = {
            "n": n, "window": "1m" if dec is raw1 and len(raw1) >= 5 else "3m",
            "min_krw": _krw(prices[0]), "max_krw": _krw(prices[-1]),
            "median_krw": _krw(int(statistics.median(prices))),
            "p25_krw": _krw(q(0.25)), "p75_krw": _krw(q(0.75)),
            "last_date": _fmt_ts(max(ts for ts, _ in dec)),
            "recent": [{"date": _fmt_ts(ts), "jpy": j, "krw": _krw(j)} for ts, j in recent],
        }

    def to_krw_series(pairs):
        return [[ts, _krw(j)] for ts, j in sorted(pairs, key=lambda x: x[0])]

    out = {
        "rate": config.JPY_KRW,
        # forward-fill 차트 끝점 = 수집 시각(오늘). 마지막 거래값을 여기까지 수평 유지.
        "as_of": int(datetime.datetime.now().timestamp() * 1000),
        "series": {"RAW": to_krw_series(raw3 or raw1),
                   "PSA9": to_krw_series(p9), "PSA10": to_krw_series(p10)},
        "raw": raw_stats,
    }
    _chart_cache[key] = out
    try:
        json.dump(_chart_cache, open(CHART_CACHE, "w", encoding="utf-8"), ensure_ascii=False)
    except Exception:
        pass
    return JSONResponse(out)


@app.post("/api/review")
async def api_review(req: Request):
    body = await req.json()
    cid, run_id, decision = body.get("card_id"), body.get("run_id"), body.get("decision")
    by = body.get("by") or "operator"
    note = body.get("note")
    status = DECISION_MAP.get(decision)
    if not status:
        return JSONResponse({"ok": False, "err": f"unknown decision {decision}"}, status_code=400)
    conn = db.init()
    cur = conn.execute(
        """UPDATE review_queue SET review_status=?, reviewed_by=?, reviewed_at=?, review_note=?
           WHERE card_id=? AND run_id=?""",
        (status, by, datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"), note, cid, run_id))
    conn.commit()
    return JSONResponse({"ok": cur.rowcount > 0, "status": status})


if __name__ == "__main__":
    print(f"[review] http://127.0.0.1:{PORT}  (cards={CARDS_DIR})")
    print("[review] ★ review_status 로컬 업데이트만 · prod write 0 · 가격 반영 0")
    uvicorn.run(app, host="127.0.0.1", port=PORT, log_level="warning")
