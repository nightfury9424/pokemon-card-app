"""SNKRDUNK 수집기 — kream_ditto.py 패턴 복제. ★네 Mac Chrome 에서 실행(샌드박스 아님).
전제: Chrome --remote-debugging-port=9222 --user-data-dir=/tmp/chrome_snkrdunk_profile 로 떠있고
      snkrdunk.com 페이지 1개 열림(로그인 권장). (KREAM 메타몽과 동일 운영)

실행:
  python snkrdunk_collect.py --selftest            # 네트워크 0, 캡처 753273 으로 파서 검증
  python snkrdunk_collect.py --apparel 753273      # 단일 수집(상세+sales+used+group)
  python snkrdunk_collect.py --discover 753273 --max 60   # group-items BFS 로 이웃 확장

원칙: evidence CSV 만. prod write·가격반영·자동 anchor 금지. 정중 크롤(랜덤 딜레이/체크포인트/stop-429/403).
수집 등급 A·PSA9·PSA10 만. SOLD=sales-history, ASK=used(status==0).
"""
import argparse, asyncio, csv, json, logging, os, random, re, sys
from datetime import datetime, timedelta, timezone

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("snkrdunk")

CDP_URL = "http://localhost:9222"
HOST = "snkrdunk.com"
B = "https://snkrdunk.com/v1/apparels/{aid}"
EP = {
    "detail": B,
    "used":   B + "/used?perPage={per}&page={page}&sizeId=0&isSaleOnly=false",
    "sales":  B + "/sales-history?size_id=0&page={page}&per_page={per}",
    "chart":  B + "/sales-chart/used?range=all&salesChartOptionId=-1",
    "group":  B + "/group-items?page={page}&perPage={per}",
}
ALLOWED = {"A", "PSA9", "PSA10"}
JST = timezone(timedelta(hours=9))
OUT = "/tmp/price_v8_snkrdunk_stage1_20260619"
DELAY = (1.5, 5.0)         # 요청간 랜덤 sleep(초)
COOLDOWN_EVERY, COOLDOWN = 30, (30, 90)  # 30요청마다 30~90초 휴식

# ───────── 파서 (직전 턴 실데이터 검증됨) ─────────
def parse_title(loc):
    m = re.search(r"\[(\w+)\s+([\d/]+)\]", loc or "")
    setc, num = (m.group(1), m.group(2)) if m else ("", "")
    head = loc[:m.start()].strip() if m else (loc or "")
    rm = re.search(r"\b(SAR|MUR|SSR|UR|SR|HR|CHR|CSR|AR|RR)\b", head)
    rar = rm.group(1) if rm else ""
    name = head[:rm.start()].strip() if rm else head
    return name, setc, num, rar


def parse_date(raw, now):
    if raw is None:
        return None
    if "時間前" in raw:
        return (now - timedelta(hours=int(re.sub(r"\D", "", raw)))).date()
    if "日前" in raw:
        return (now - timedelta(days=int(re.sub(r"\D", "", raw)))).date()
    if "週間前" in raw:
        return (now - timedelta(weeks=int(re.sub(r"\D", "", raw)))).date()
    try:
        return datetime.strptime(raw, "%Y/%m/%d").date()
    except Exception:
        return None


def recency_bucket(d, ref):
    if not d:
        return "UNKNOWN"
    age = (ref - d).days
    return ("SOLD_0_60D" if age <= 60 else "SOLD_61_90D" if age <= 90 else
            "SOLD_91_180D" if age <= 180 else "SOLD_181_365D" if age <= 365 else "SOLD_365D_PLUS")


def norm_grade(c):
    s = (c or "").upper().replace("中古", "").strip()
    return s if s in ALLOWED else None


def parse_sales(history, now):
    """sales-history history[] → SOLD rows (A/PSA9/PSA10 만)."""
    out = []
    ref = now.date()
    for h in history:
        g = norm_grade(h.get("condition"))
        if not g:
            continue
        d = parse_date(h.get("date"), now)
        out.append({"sold_date_raw": h.get("date"), "sold_date": d.isoformat() if d else "",
                    "condition_grade_normalized": g, "price_jpy": h.get("price"),
                    "price_type": "SOLD_VERIFIED", "recency_bucket": recency_bucket(d, ref),
                    "evidence_source_section": "RECENT_SALES_HISTORY"})
    return out


def ladder(sales):
    import statistics
    r = {}
    for g in ("A", "PSA9", "PSA10"):
        v = [s["price_jpy"] for s in sales if s["condition_grade_normalized"] == g and s.get("sold_date")]
        r[g] = {"median": round(statistics.median(v)) if v else None, "n": len(v),
                "min": min(v) if v else None, "max": max(v) if v else None}
    a, p9, p10 = r["A"]["median"], r["PSA9"]["median"], r["PSA10"]["median"]
    st = "LADDER_INCOMPLETE"
    if a and p10 and a > p10:
        st = "RAW_OVER_PSA10"
    elif p9 and p10 and p9 > p10:
        st = "PSA9_OVER_PSA10"
    elif a and p10:
        st = "LADDER_OK"
    r["status"] = st
    return r


# ───────── CDP fetch (kream 패턴) ─────────
async def fetch_json(target, url):
    res = await target.evaluate(
        """async (u) => { const r = await fetch(u, {credentials:'include', headers:{'accept':'application/json'}});
                          return { status: r.status, body: await r.text() }; }""", url)
    if res.get("status") in (429, 403):
        log.error("HTTP %s on %s → 정중 중단(stop). 잠시 후 재시도.", res["status"], url)
        sys.exit(7)
    if res.get("status") != 200:
        log.warning("HTTP %s on %s", res.get("status"), url)
        return None
    try:
        return json.loads(res["body"])
    except Exception:
        log.error("JSON 파싱 실패 → 응답구조 변경 의심: %s", url)
        sys.exit(4)


async def get_target(pw):
    try:
        browser = await pw.chromium.connect_over_cdp(CDP_URL, timeout=5000)
    except Exception as e:
        log.error("CDP attach 실패(%s). Chrome 9222 떠있어야 함.", e)
        sys.exit(2)
    t = next((p for ctx in browser.contexts for p in ctx.pages if HOST in (p.url or "")), None)
    if t is None:
        log.error("snkrdunk.com 페이지 없음. 인스턴스에 1개 열어둘 것.")
        sys.exit(3)
    log.info("[CDP] attached page=%s", t.url)
    return t


async def collect_apparel(target, aid, now):
    """단일 apparel 수집 → dict(detail, sales, ladder, group)."""
    detail = await fetch_json(target, EP["detail"].format(aid=aid))
    await asyncio.sleep(random.uniform(*DELAY))
    sales_raw, page = [], 1
    while page <= 5:  # sales-history 페이징(최대 5p=100건, 60일이면 보통 1p로 충분)
        j = await fetch_json(target, EP["sales"].format(aid=aid, page=page, per=20))
        hist = (j or {}).get("history", [])
        if not hist:
            break
        sales_raw += hist
        if len(hist) < 20:
            break
        page += 1
        await asyncio.sleep(random.uniform(*DELAY))
    group = await fetch_json(target, EP["group"].format(aid=aid, page=1, per=10))
    sales = parse_sales(sales_raw, now)
    name, setc, num, rar = parse_title((detail or {}).get("localizedName", ""))
    return {"aid": aid, "detail": detail, "name": name, "set": setc, "num": num, "rar": rar,
            "image": (detail or {}).get("primaryMedia", {}).get("imageUrl", ""),
            "sales": sales, "ladder": ladder(sales),
            "group": [(g["id"], g.get("localizedName", "")) for g in (group or {}).get("apparels", [])]}


# ───────── selftest (네트워크 0) ─────────
SAMPLE_753273 = {"localizedName": "メガピクシーex SAR [M3 112/080](拡張パック「ムニキスゼロ」)",
                 "primaryMedia": {"imageUrl": "https://cdn.snkrdunk.com/upload_bg_removed/20260122103135-0.webp"}}
SAMPLE_SALES = [{"price": 3200, "date": "21時間前", "condition": "A"}, {"price": 3000, "date": "1日前", "condition": "A"},
    {"price": 49800, "date": "2日前", "condition": "PSA10"}, {"price": 16999, "date": "2日前", "condition": "PSA10"},
    {"price": 15900, "date": "3日前", "condition": "PSA10"}, {"price": 16000, "date": "2026/06/13", "condition": "PSA10"},
    {"price": 17000, "date": "2026/06/11", "condition": "PSA10"}, {"price": 3500, "date": "2026/06/10", "condition": "A"},
    {"price": 33000, "date": "2026/06/09", "condition": "PSA10"}, {"price": 3800, "date": "2026/06/08", "condition": "A"},
    {"price": 52000, "date": "2026/06/04", "condition": "PSA10"}, {"price": 16500, "date": "2026/06/03", "condition": "PSA10"}]


def selftest():
    now = datetime(2026, 6, 19, 21, 39, tzinfo=JST)
    name, setc, num, rar = parse_title(SAMPLE_753273["localizedName"])
    assert (name, setc, num, rar) == ("メガピクシーex", "M3", "112/080", "SAR"), (name, setc, num, rar)
    sales = parse_sales(SAMPLE_SALES, now)
    assert all(s["condition_grade_normalized"] in ALLOWED for s in sales)
    assert all(s["recency_bucket"] == "SOLD_0_60D" for s in sales)
    lad = ladder(sales)
    print(f"[selftest] title OK: {name}/{setc}/{num}/{rar}")
    print(f"[selftest] sales={len(sales)} A={lad['A']} PSA10={lad['PSA10']} status={lad['status']}")
    assert lad["status"] == "LADDER_OK" and lad["A"]["median"] < lad["PSA10"]["median"]
    print("[selftest] ✅ 파서 검증 통과 (네트워크 0). CDP/fetch 레이어는 Mac Chrome 에서.")


async def amain(args):
    from playwright.async_api import async_playwright
    now = datetime.now(JST)
    async with async_playwright() as pw:
        target = await get_target(pw)
        seeds = [args.apparel or args.discover]
        seen, queue, results = set(), list(seeds), []
        while queue and len(seen) < (args.max or 1):
            aid = queue.pop(0)
            if aid in seen:
                continue
            seen.add(aid)
            log.info("[collect] apparel %s (%d/%d)", aid, len(seen), args.max or 1)
            r = await collect_apparel(target, aid, now)
            results.append(r)
            if args.discover:  # BFS 이웃 확장
                for gid, _ in r["group"]:
                    if gid not in seen:
                        queue.append(gid)
            if len(seen) % COOLDOWN_EVERY == 0:
                await asyncio.sleep(random.uniform(*COOLDOWN))
            await asyncio.sleep(random.uniform(*DELAY))
        _write(results)
        log.info("[done] %d apparel → %s", len(results), OUT)


def _write(results):
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/snkrdunk_recent_sales_by_apparel.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(["apparel_id", "name", "set", "num", "rarity", "sold_date", "condition", "price_jpy", "price_type", "recency_bucket"])
        for r in results:
            for s in r["sales"]:
                w.writerow([r["aid"], r["name"], r["set"], r["num"], r["rar"], s["sold_date"], s["condition_grade_normalized"], s["price_jpy"], s["price_type"], s["recency_bucket"]])
    with open(f"{OUT}/snkrdunk_jp_ladder.csv", "w", newline="") as f:
        w = csv.writer(f); w.writerow(["apparel_id", "name", "set", "num", "rarity", "image_url", "A_median", "A_n", "PSA9_median", "PSA10_median", "PSA10_n", "ladder_status"])
        for r in results:
            L = r["ladder"]; w.writerow([r["aid"], r["name"], r["set"], r["num"], r["rar"], r["image"], L["A"]["median"], L["A"]["n"], L["PSA9"]["median"], L["PSA10"]["median"], L["PSA10"]["n"], L["status"]])


# ═════════ 직접 HTTP range scan (멀티스레드) — snkrdunk 상세/판매내역 공개 ═════════
import urllib.request, urllib.error, threading, time
from concurrent.futures import ThreadPoolExecutor, as_completed

UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36")
HTTP_DETAIL = "https://snkrdunk.com/v1/apparels/{aid}"
HTTP_SALES = "https://snkrdunk.com/v1/apparels/{aid}/sales-history?size_id=0&page={page}&per_page=20"
SCANNER = "http://localhost:8082"
SNK_CACHE = "scanner/data/snkrdunk_cache"   # DATA_DIR 상대(identify_path 용)
STOP = threading.Event()


def http_json(url, timeout):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, None
    except Exception:
        return None, None


def is_pokemon_single(d):
    """detail 응답이 우리 대상(포켓몬 싱글카드)인가."""
    if not d or not d.get("apparelInfo", {}).get("isTradingCard"):
        return False
    if "trading-card-single" not in [c.get("name") for c in d.get("categories", [])]:
        return False
    if "pokemon" not in [b.get("id") for b in d.get("brands", [])]:
        return False
    if not (d.get("productNumber", "") or "").startswith("pkmn-tcg-"):
        return False
    img = d.get("primaryMedia", {}).get("imageUrl", "")
    return bool(img) and "uploads/media/" not in img  # placeholder 제외


def scan_one(aid, timeout, retries, dmin, dmax):
    if STOP.is_set():
        return ("ABORT", aid, None, None)
    time.sleep(random.uniform(dmin, dmax))
    for att in range(retries + 1):
        st, body = http_json(HTTP_DETAIL.format(aid=aid), timeout)
        if st in (429, 403):
            STOP.set(); log.error("HTTP %s @ %s → 정중 중단(STOP). 잠시 후 재개.", st, aid)
            return ("STOP", aid, st, None)
        if st == 404:
            return ("NOT_FOUND", aid, st, None)
        if st == 200 and body:
            try:
                d = json.loads(body)
            except Exception:
                return ("PARSE_ERR", aid, st, None)
            if is_pokemon_single(d):
                name, setc, num, rar = parse_title(d.get("localizedName", ""))
                return ("POKEMON", aid, st, {"productNumber": d.get("productNumber"), "jp_title": d.get("localizedName"),
                        "en_name": d.get("name"), "image_url": d["primaryMedia"]["imageUrl"], "name": name,
                        "set": setc, "number": num, "rarity": rar, "usedListingCount": d.get("usedListingCount")})
            return ("NON_PKMN", aid, st, None)
        time.sleep(1.5 * (att + 1))
    return ("ERR", aid, st, None)


def scan_range(a):
    done = set()
    if a.resume and os.path.exists(a.checkpoint):
        for r in csv.DictReader(open(a.checkpoint)):
            done.add(int(r["apparel_id"]))
    ids = [i for i in range(a.scan_apparel_range[0], a.scan_apparel_range[1] + 1) if i not in done]
    if a.limit:
        ids = ids[:a.limit]
    log.info("scan %d ids (resume skip %d) workers=%d timeout=%s", len(ids), len(done), a.workers, a.timeout)
    if a.dry_run:
        log.info("[dry-run] 스캔 안 함."); return
    os.makedirs(OUT, exist_ok=True)
    new_cp = not os.path.exists(a.checkpoint)
    cp = open(a.checkpoint, "a", newline=""); cpw = csv.writer(cp)
    if new_cp:
        cpw.writerow(["apparel_id", "status", "product_number", "set", "number", "rarity"])
    cat_new = not os.path.exists(f"{OUT}/snkrdunk_apparel_catalog_scanned.csv")
    cat = open(f"{OUT}/snkrdunk_apparel_catalog_scanned.csv", "a", newline=""); catw = csv.writer(cat)
    if cat_new:
        catw.writerow(["apparel_id", "detail_url", "jp_title", "en_name", "product_number", "image_url", "set", "number", "rarity", "used_listing_count"])
    lock = threading.Lock(); n = pk = 0
    with ThreadPoolExecutor(max_workers=a.workers) as ex:
        futs = {ex.submit(scan_one, i, a.timeout, 2, a.delay_min, a.delay_max): i for i in ids}
        for f in as_completed(futs):
            tag, aid, st, info = f.result()
            n += 1
            with lock:
                cpw.writerow([aid, tag, (info or {}).get("productNumber", ""), (info or {}).get("set", ""), (info or {}).get("number", ""), (info or {}).get("rarity", "")])
                if tag == "POKEMON":
                    pk += 1
                    catw.writerow([aid, f"https://snkrdunk.com/apparels/{aid}", info["jp_title"], info["en_name"], info["productNumber"], info["image_url"], info["set"], info["number"], info["rarity"], info["usedListingCount"]])
            if n % 500 == 0:
                cp.flush(); cat.flush(); log.info("  진행 %d/%d (포켓몬 %d)", n, len(ids), pk)
            if STOP.is_set():
                log.error("STOP 감지 → 남은 작업 취소."); break
            if a.cooldown_every and n % a.cooldown_every == 0:
                time.sleep(random.uniform(a.cooldown_min, a.cooldown_max))
    cp.close(); cat.close()
    log.info("[scan done] %d 처리 / 포켓몬 싱글 %d → snkrdunk_apparel_catalog_scanned.csv", n, pk)


# ═════════ match-and-collect: 스캔 카탈로그 → 이미지매칭 → MATCH_HIGH만 sales-history ═════════
def load_registered(path):
    reg = {}
    for r in csv.DictReader(open(path)):
        ref = r.get("jp_ref", "") or ""
        num = ref.rsplit("-", 1)[-1] if "-" in ref else ""
        if not num:  # jp_ref 빈칸(promo 등) fallback: official_card_code 끝 2~3자리
            m = re.search(r"(\d{2,3})$", r.get("official_card_code", "") or "")
            num = m.group(1) if m else ""
        reg[r["card_id"]] = {"name": r.get("name_ko", ""), "rarity": r.get("rarity_code", ""),
                             "code": r.get("official_card_code", ""), "num": num}
    return reg


def identify_path(rel):
    st, body = http_json(f"{SCANNER}/identify_path?path={urllib.parse.quote(rel)}", 10)
    if st != 200 or not body:
        return None
    try:
        d = json.loads(body)
        return d.get("status"), (d.get("data") or {}).get("topResult")
    except Exception:
        return None


def match_and_collect(a):
    import urllib.parse
    reg = load_registered(a.registered_csv)
    log.info("등록 카드 %d장 로드. 스캔 카탈로그 매칭 시작.", len(reg))
    os.makedirs(SNK_CACHE, exist_ok=True)
    cands, evid = [], []
    cat_path = getattr(a, "catalog_csv", None) or f"{OUT}/snkrdunk_apparel_catalog_scanned.csv"
    cat = list(csv.DictReader(open(cat_path)))
    log.info("catalog=%s (%d행)", cat_path, len(cat))
    for r in (cat[:a.limit] if a.limit else cat):
        aid = r["apparel_id"]; img_url = r["image_url"]
        local = f"{SNK_CACHE}/{aid}.webp"
        if not os.path.exists(local):
            try:
                urllib.request.urlretrieve(urllib.request.Request(img_url, headers={"User-Agent": UA}).full_url, local)
            except Exception:
                cands.append({**r, "match_status": "IMAGE_FETCH_FAILED", "card_id": "", "score": ""}); continue
            time.sleep(random.uniform(a.delay_min, a.delay_max))
        res = identify_path(f"snkrdunk_cache/{aid}.webp")
        if not res:
            cands.append({**r, "match_status": "SCANNER_ERR", "card_id": "", "score": ""}); continue
        status, top = res
        cid = (top or {}).get("cardId", ""); score = (top or {}).get("score", "")
        registered = cid in reg
        # ★set/number crosscheck 강제: 우리 번호(jp_ref 접미 "55") vs snkrdunk 번호("112/080"→"112")
        snk_num = (r.get("number", "") or "").split("/")[0].lstrip("0")
        our_num = (reg[cid]["num"] if registered else "").lstrip("0")
        num_ok = bool(our_num) and our_num == snk_num
        our_rar = reg[cid]["rarity"] if registered else ""
        rar_ok = (not our_rar) or (not r.get("rarity")) or (our_rar == r.get("rarity"))
        if status == "success" and registered and num_ok and rar_ok:
            ms = "MATCH_HIGH"
        elif status == "success" and registered:
            ms = "MATCH_MEDIUM"      # 이미지=우리카드인데 번호/레어도 불일치 → 사람검토(evidence 제외)
        elif status == "success" and not registered:
            ms = "OUT_OF_SCOPE"      # 신세트/미등록(M2·M3 등) — catalog엔 남고 evidence 제외
        elif status == "low_confidence":
            ms = "MATCH_LOW"
        else:
            ms = "MISMATCH_CARD"
        cands.append({**r, "match_status": ms, "card_id": cid, "card_name": reg.get(cid, {}).get("name", ""),
                      "score": score, "set_number_crosscheck": num_ok, "rarity_match": rar_ok})
        if ms == "MATCH_HIGH":  # ★MATCH_HIGH만 sales-history 호출
            sraw, page = [], 1
            while page <= 5 and not STOP.is_set():
                st, body = http_json(HTTP_SALES.format(aid=aid, page=page), a.timeout or 8)
                if st in (429, 403):
                    STOP.set(); break
                j = json.loads(body) if (st == 200 and body) else {}
                h = j.get("history", [])
                sraw += h
                if len(h) < 20:
                    break
                page += 1; time.sleep(random.uniform(a.delay_min, a.delay_max))
            sales = parse_sales(sraw, datetime.now(JST))
            L = ladder(sales)
            for s in sales:
                evid.append({"card_id": cid, "apparel_id": aid, "source": "SNKRDUNK", "condition_grade": s["condition_grade_normalized"],
                             "price_jpy": s["price_jpy"], "price_type": "SOLD_VERIFIED", "sold_date": s["sold_date"],
                             "recency_bucket": s["recency_bucket"], "scanner_score": score, "match_confidence": "HIGH",
                             "ladder_status": L["status"], "validation_status": "VALID"})
            time.sleep(random.uniform(a.delay_min, a.delay_max))
    with open(f"{OUT}/snkrdunk_to_pokefolio_match_candidates.csv", "w", newline="") as f:
        cols = ["apparel_id", "jp_title", "set", "number", "rarity", "image_url", "card_id", "card_name", "score", "set_number_crosscheck", "rarity_match", "match_status"]
        w = csv.DictWriter(f, fieldnames=cols, extrasaction="ignore"); w.writeheader(); w.writerows(cands)
    with open(f"{OUT}/snkrdunk_evidence_mapped.csv", "w", newline="") as f:
        cols = ["card_id", "apparel_id", "source", "condition_grade", "price_jpy", "price_type", "sold_date", "recency_bucket", "scanner_score", "match_confidence", "ladder_status", "validation_status"]
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(evid)
    mh = sum(1 for c in cands if c["match_status"] == "MATCH_HIGH")
    log.info("[match done] 카탈로그 %d → MATCH_HIGH %d → evidence %d행. (OUT_OF_SCOPE/MISMATCH 제외)", len(cands), mh, len(evid))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--apparel")
    ap.add_argument("--discover")
    ap.add_argument("--max", type=int, default=1)
    ap.add_argument("--scan-apparel-range", nargs=2, type=int, metavar=("START", "END"))
    ap.add_argument("--match-and-collect", action="store_true")
    ap.add_argument("--registered-csv", default=f"{OUT}/target_pokefolio_all_for_snkrdunk.csv")
    ap.add_argument("--workers", type=int, default=16)
    ap.add_argument("--timeout", type=float, default=3.0)
    ap.add_argument("--delay-min", type=float, default=0.0)
    ap.add_argument("--delay-max", type=float, default=0.05)
    ap.add_argument("--cooldown-every", type=int, default=10000)
    ap.add_argument("--cooldown-min", type=float, default=20.0)
    ap.add_argument("--cooldown-max", type=float, default=60.0)
    ap.add_argument("--checkpoint", default=f"{OUT}/apparel_scan_checkpoint.csv")
    ap.add_argument("--resume", action="store_true")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--catalog-csv")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        selftest()
    elif a.scan_apparel_range:
        scan_range(a)
    elif a.match_and_collect:
        match_and_collect(a)
    elif a.apparel or a.discover:
        asyncio.run(amain(a))
    else:
        ap.print_help()
