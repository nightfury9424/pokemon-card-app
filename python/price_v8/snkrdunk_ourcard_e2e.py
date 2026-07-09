#!/usr/bin/env python3
"""SNKRDUNK 검수툴 — **우리 전체 카탈로그(3,755) 기준** 일반화.

메인축 = 우리 카드 전부. 각 카드에 SNKRDUNK 직접 후보(set+번호)를 붙이고, 후보 이미지가 있으면
우리 스캐너(DINOv2+FAISS) top5로 교차검증. SNK 직접 ID 없는 카드는 SNK_ID_NOT_FOUND(=resolver 큐).
SNKRDUNK엔 있고 우리 DB엔 없는 카드는 하단 별도 섹션.

CLI:
  python snkrdunk_ourcard_e2e.py [--catalog ...] [--sets ALL|M3,SV4A] \
    [--out-csv ...] [--out-html ...] [--topk 5]

read-only: prod DB write 0, raw 가격 적재 0, 검색링크 0 (직접 apparel URL만).
"""
import csv, os, re, json, time, statistics, html, urllib.request, urllib.parse, argparse
from collections import Counter, defaultdict
from PIL import Image

ROOT = "/Users/fury/pokemon-card-app"
SNK_DIR = "/Users/fury/Downloads/price_v8_snkrdunk"
# ★ source of truth = 2026-06-20 백업된 41,610 포켓몬 apparel catalog (영구백업)
APPAREL_CSV = os.path.expanduser("~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv")
RESOLVER_INDEX = f"{ROOT}/python/price_v8/snk_pokemon_index.csv"     # id-scan resolver(보조)
LISTING_INDEX = f"{ROOT}/python/price_v8/snk_listing_index.csv"      # listing resolver(보조)
SALES_CSV = f"{SNK_DIR}/snkrdunk_recent_sales_by_apparel.csv"
IMG_OUT = f"{ROOT}/scanner/data/snk_images"
IMG_REL = "snk_images"
SCANNER = "http://localhost:8082/identify_path"
SCAN_CONFIDENT = 0.55
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

ap = argparse.ArgumentParser()
ap.add_argument("--catalog", default=f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv")
ap.add_argument("--sets", default="ALL", help="ALL 또는 콤마구분 set_code")
ap.add_argument("--out-csv", default=f"{ROOT}/python/price_v8/snkrdunk_ourcard_review_all.csv")
ap.add_argument("--out-html", default=f"{ROOT}/snkrdunk_ourcard_review_all.html")
ap.add_argument("--topk", type=int, default=5)
args = ap.parse_args()
SET_FILTER = None if args.sets.upper() == "ALL" else {s.strip().upper() for s in args.sets.split(",")}
os.makedirs(IMG_OUT, exist_ok=True)

def num_int(s):
    if not s: return None
    m = re.search(r"(\d+)", str(s).split("/")[0].split("-")[-1])
    return int(m.group(1)) if m else None

def parse_ref(ref):
    """m3_ja-97 -> ('M3', 97). NO_JP/빈값 -> (None, None)."""
    m = re.match(r"^([a-z0-9]+)_ja-(\d+)$", (ref or "").strip())
    return (m.group(1).upper(), int(m.group(2))) if m else (None, None)

def our_img_rel(cid):
    for suf in ("_jp", "_ko", "_en"):
        if os.path.exists(f"{ROOT}/scanner/data/cards/{cid}{suf}.png"):
            return f"cards/{cid}{suf}.png"
    return ""

# ---- 우리 카탈로그 전체 ----
our_cards = []
with open(args.catalog, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        ref = (row.get("jp_scrydex_ref") or "").strip()
        sc, n = parse_ref(ref)
        if SET_FILTER and sc not in SET_FILTER:
            continue
        our_cards.append({
            "card_id": row["card_id"], "name": row["name"], "code": row["official_card_code"],
            "num": row["collection_number"], "set": sc, "num_int": n,
            "rarity": row["rarity_code"], "jp_ref": ref, "img": our_img_rel(row["card_id"]),
        })
our_index = {(c["set"], c["num_int"]): c for c in our_cards if c["set"]}
print(f"[우리 카탈로그] {len(our_cards)}장 (set 파싱 {sum(1 for c in our_cards if c['set'])}, NO_JP {sum(1 for c in our_cards if not c['set'])})")

# ---- SNKRDUNK apparel 인덱스 (set, num) — 스캔카탈로그 + resolver 인덱스 merge ----
apparels = []
seen_aid = set()
for src in (LISTING_INDEX, APPAREL_CSV, RESOLVER_INDEX):   # listing 우선(주력)
    if not os.path.exists(src):
        continue
    with open(src, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            aid = str(row.get("apparel_id") or "").strip()
            if not aid or aid in seen_aid:
                continue
            seen_aid.add(aid)
            sc = (row.get("set") or "").upper()
            row["_set"] = sc
            row["_num"] = num_int(row.get("number") or row.get("product_number"))
            if SET_FILTER and sc not in SET_FILTER:
                continue
            apparels.append(row)
snk_index = defaultdict(list)
for a in apparels:
    snk_index[(a["_set"], a["_num"])].append(a)
# 크롤(해석)된 세트 = 인덱스에 등장한 set. 그 세트 안에서 못 찾으면 SEARCH_FAILED, 아예 안 긁은 세트면 NOT_COLLECTED.
crawled_sets = {a["_set"] for a in apparels if a["_set"]}
print(f"[SNKRDUNK apparel] {len(apparels)}개 (merge: 스캔+resolver) · 크롤된 set {len(crawled_sets)}개: {sorted(crawled_sets)}")

# ---- sold ----
sales = {}
if os.path.exists(SALES_CSV):
    tmp = defaultdict(list)
    with open(SALES_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try: p = int(float(row["price_jpy"]))
            except: continue
            tmp[row["apparel_id"]].append((p, row.get("sold_date", "")))
    for aid, v in tmp.items():
        ps = [p for p, _ in v]
        sales[aid] = {"count": len(ps), "median": int(statistics.median(ps)),
                      "min": min(ps), "max": max(ps), "latest": max((d for _, d in v if d), default="")}

# ---- 이미지/스캐너 ----
def fetch_png(aid, url):
    png = f"{IMG_OUT}/{aid}.png"
    if os.path.exists(png) and os.path.getsize(png) > 1000: return png
    if not url: return None
    raw = f"{IMG_OUT}/{aid}.src"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            open(raw, "wb").write(r.read())
        Image.open(raw).convert("RGB").save(png, "PNG"); os.remove(raw)
        time.sleep(0.4); return png
    except Exception as e:
        print(f"  img fail {aid}: {e}"); return None

def scan(rel):
    try:
        with urllib.request.urlopen(f"{SCANNER}?path={urllib.parse.quote(rel)}", timeout=60) as r:
            d = json.load(r)
    except Exception as e:
        return None, str(e)
    st = d.get("status")
    if st in ("success", "low_confidence") and (d.get("data") or {}).get("topResult"):
        return d["data"], (st if st == "low_confidence" else None)
    return None, st or "scan error"

# 우리 카드와 매칭되는 apparel만 스캔(카드당 1개). SNKRDUNK_ONLY 는 스캔 안 함(정보용).
# 스캔 캐시(재개가능): 한 번 스캔한 apparel 은 재실행 시 건너뜀 → 점진적으로 채움.
our_set_codes = {c["set"] for c in our_cards if c["set"]}
SCAN_CACHE = f"{ROOT}/python/price_v8/snk_scan_cache.json"
cache = {}
if os.path.exists(SCAN_CACHE):
    try: cache = json.load(open(SCAN_CACHE))
    except Exception: cache = {}

match_aids = {}
for c in our_cards:
    cands = snk_index.get((c["set"], c["num_int"])) if c["set"] else None
    if cands:
        match_aids[str(cands[0]["apparel_id"])] = cands[0]
todo = [a for aid, a in match_aids.items() if aid not in cache]
print(f"[스캐너] 매칭 apparel {len(match_aids)}개 중 미스캔 {len(todo)}개 다운로드+스캔 (캐시 {len(cache)})...")
snk_scan = {}
NO_SCAN = (os.environ.get("E2E_NO_SCAN") == "1")
for i, a in enumerate(todo, 1):
    if NO_SCAN:
        break
    aid = str(a["apparel_id"])
    png = fetch_png(aid, a.get("image_url", ""))
    rel = f"{IMG_REL}/{aid}.png" if png else None
    top1, top5, note = {}, [], ("no_image" if not png else None)
    if rel:
        data, note = scan(rel)
        if data:
            tr = data["topResult"]
            top1 = {"id": tr["cardId"], "name": tr["name"], "rarity": tr.get("rarityCode", ""),
                    "ref": tr.get("scrydexRef", ""), "score": round(float(tr["score"]), 4)}
            for c in data.get("candidates", [])[:args.topk]:
                top5.append({"cardId": c["cardId"], "name": c["name"], "rarity": c.get("rarityCode", ""),
                             "ref": c.get("scrydexRef", ""), "score": round(float(c["score"]), 4)})
    cache[aid] = {"img": rel, "top1": top1, "top5": top5, "note": note}
    if i % 25 == 0:
        json.dump(cache, open(SCAN_CACHE, "w"), ensure_ascii=False)
        print(f"  스캔 {i}/{len(todo)}")
json.dump(cache, open(SCAN_CACHE, "w"), ensure_ascii=False)
# snk_scan = 매칭 apparel 의 캐시값(+sold)
for aid in match_aids:
    if aid in cache:
        snk_scan[aid] = {**cache[aid], "sold": sales.get(aid)}

# ---- 우리카드 기준 행 생성 ----
def classify(our, ap_row, s):
    if not our["img"]:
        return "OUR_IMAGE_MISSING", "REVIEW"
    if not ap_row:
        # 기존 CSV에 대응 SNK ID 없음 (또는 JP ref 자체 없음)
        if not our["set"]:
            return "NO_JP_REF", "LOW"
        return "SNK_ID_NOT_IN_CSV", "LOW"
    if not s or not s.get("img"):
        return "SNK_IMAGE_MISSING", "MED"
    t1 = s.get("top1") or {}
    has_scan = bool(t1) and t1.get("score") is not None
    conf = has_scan and t1["score"] >= SCAN_CONFIDENT
    if has_scan and t1["id"] == our["card_id"]:
        return "HIGH_CONFIDENCE", "HIGH"
    if conf and t1["id"] != our["card_id"]:
        return "CONFLICT", "REVIEW"
    return "TEXT_MATCH_ONLY", "MED"

rows = []
for c in our_cards:
    cands = snk_index.get((c["set"], c["num_int"])) if c["set"] else None
    ap_row = cands[0] if cands else None
    s = snk_scan.get(ap_row["apparel_id"]) if ap_row else None
    st, cf = classify(c, ap_row, s)
    note = (s["note"] if s and s.get("note") else "")
    if not c["set"]:
        note = "JP ref 없음(NO_JP)"
    rows.append({"our": c, "snk": ap_row, "scan": s, "status": st, "conf": cf, "note": note})

# SNKRDUNK only — 우리 세트에 속하지만 우리가 안 가진 카드만 (외부세트 제외). HTML 비대화 방지 캡.
ONLY_CAP = int(os.environ.get("E2E_ONLY_CAP", "300"))
only_all = [a for a in apparels if (a["_set"], a["_num"]) not in our_index and a["_set"] in our_set_codes]
only_total = len(only_all)
only_rows = [{"snk": a, "scan": snk_scan.get(a["apparel_id"])} for a in only_all[:ONLY_CAP]]

# ---- CSV ----
COLS = ["our_card_id","our_name","our_jp_ref","our_set_code","our_card_no","our_rarity","our_image_path",
        "snkrdunk_id","snkrdunk_url","snkrdunk_title","snkrdunk_product_number","snkrdunk_image_url",
        "snkrdunk_image_cache_path","text_match_card_id","scanner_top1_card_id","scanner_top1_name",
        "scanner_top1_score","scanner_top5_json","match_status","confidence","source_set","notes"]
def csv_row(r):
    o = r["our"]; a = r["snk"] or {}; s = r["scan"] or {}; t1 = s.get("top1") or {}
    return {"our_card_id": o["card_id"], "our_name": o["name"], "our_jp_ref": o["jp_ref"],
            "our_set_code": o["set"] or "", "our_card_no": o["num"], "our_rarity": o["rarity"],
            "our_image_path": o["img"], "snkrdunk_id": a.get("apparel_id",""),
            "snkrdunk_url": a.get("detail_url",""), "snkrdunk_title": a.get("jp_title",""),
            "snkrdunk_product_number": a.get("product_number",""), "snkrdunk_image_url": a.get("image_url",""),
            "snkrdunk_image_cache_path": (s.get("img") or ""),
            "text_match_card_id": o["card_id"] if r["snk"] else "",
            "scanner_top1_card_id": t1.get("id",""), "scanner_top1_name": t1.get("name",""),
            "scanner_top1_score": t1.get("score",""),
            "scanner_top5_json": json.dumps(s.get("top5",[]), ensure_ascii=False),
            "match_status": r["status"], "confidence": r["conf"], "source_set": o["set"] or "", "notes": r["note"]}
with open(args.out_csv, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=COLS); w.writeheader()
    for r in rows: w.writerow(csv_row(r))
    for r in only_rows:
        a = r["snk"]; s = r["scan"] or {}; t1 = s.get("top1") or {}
        w.writerow({"our_card_id":"","our_name":"","our_jp_ref":"","our_set_code":"","our_card_no":a.get("number",""),
            "our_rarity":a.get("rarity",""),"our_image_path":"","snkrdunk_id":a["apparel_id"],
            "snkrdunk_url":a.get("detail_url",""),"snkrdunk_title":a.get("jp_title",""),
            "snkrdunk_product_number":a.get("product_number",""),"snkrdunk_image_url":a.get("image_url",""),
            "snkrdunk_image_cache_path":(s.get("img") or ""),"text_match_card_id":"",
            "scanner_top1_card_id":t1.get("id",""),"scanner_top1_name":t1.get("name",""),"scanner_top1_score":t1.get("score",""),
            "scanner_top5_json":json.dumps(s.get("top5",[]),ensure_ascii=False),
            "match_status":"SNKRDUNK_ONLY","confidence":"—","source_set":a.get("set",""),"notes":""})
print(f"\n[CSV] {args.out_csv}")

# ---- 통계 ----
stat = Counter(r["status"] for r in rows)
matched = sum(1 for r in rows if r["snk"])
scanned = sum(1 for r in rows if r["scan"] and r["scan"].get("img"))
print("[통계]")
print(f"  1. 전체 우리 카드      : {len(rows)}")
print(f"  2. HTML row(메인)      : {len(rows)}")
print(f"  3. SNK 직접후보 보유    : {matched}")
print(f"  4. scanner 실행        : {scanned}")
print(f"  5. HIGH_CONFIDENCE     : {stat.get('HIGH_CONFIDENCE',0)}")
print(f"  6. CONFLICT            : {stat.get('CONFLICT',0)}")
print(f"  7. SNK_ID_NOT_IN_CSV   : {stat.get('SNK_ID_NOT_IN_CSV',0)}  (기존 CSV에 대응 SNK id 없음)")
print(f"  8. NO_JP_REF           : {stat.get('NO_JP_REF',0)}  (우리 카드에 jp_ref 없음)")
print(f"  9. SNKRDUNK only       : {only_total} (HTML 표시 {len(only_rows)})")
print(f"     (그외 TEXT_ONLY {stat.get('TEXT_MATCH_ONLY',0)} / SNK_IMG_MISSING {stat.get('SNK_IMAGE_MISSING',0)} / OUR_IMG_MISSING {stat.get('OUR_IMAGE_MISSING',0)})")

# ---- HTML ----
def esc(s): return html.escape(str(s if s is not None else ""))
SC = {"HIGH_CONFIDENCE":"#1a7f37","CONFLICT":"#cf222e","TEXT_MATCH_ONLY":"#9a6700",
      "SNK_IMAGE_MISSING":"#bc4c00","SNK_ID_NOT_IN_CSV":"#6e7781","NO_JP_REF":"#9a6700",
      "OUR_IMAGE_MISSING":"#cf222e","SNKRDUNK_ONLY":"#8250df"}
def t5_html(s, our_id):
    if not s or not s.get("top5"): return "<i>스캐너 결과 없음</i>"
    out=[]
    for j,c in enumerate(s["top5"]):
        hit="★" if c["cardId"]==our_id else ""
        out.append(f"<div class='t5{' t5hit' if hit else ''}'><img loading='lazy' src='scanner/data/cards/{esc(c['cardId'])}_jp.png' onerror=\"this.style.opacity=.12\">"
                   f"<div class='t5m'><b>{j+1}.{hit}</b> {esc(c['name'])} <span class='rar'>{esc(c['rarity'])}</span><br>"
                   f"<span class='ref'>{esc(c['ref'])}</span> · <span class='sc'>{c['score']}</span></div></div>")
    return "".join(out)
def sold_html(s):
    so=s and s.get("sold")
    if not so: return ""
    return (f"<div class='sold'>💴 sold {so['count']}건 · median <b>¥{so['median']:,}</b> "
            f"(¥{so['min']:,}~¥{so['max']:,}) · 최근 {esc(so['latest'])}</div>")

def full_card(r):
    o=r["our"]; a=r["snk"]; s=r["scan"]; sc=SC.get(r["status"],"#333"); cid=o["card_id"]
    snk_img=f"scanner/data/{s['img']}" if s and s.get("img") else ""
    t1=(s.get("top1") or {}) if s else {}
    right=(f"<img class='big' loading='lazy' src='{esc(snk_img)}' onerror=\"this.style.opacity=.12\">"
           f"<div class='meta'><b>{esc(a.get('jp_title',''))}</b><br><span class='mono'>{esc(a.get('product_number',''))}</span> · {esc(a.get('rarity',''))}<br>"
           f"<a href='{esc(a.get('detail_url',''))}' target='_blank'>▶ {esc(a.get('detail_url',''))}</a></div>{sold_html(s)}") if a else "<div class='nomatch'>—</div>"
    cross=(f"<div class='mrow'>텍스트 → <b>{esc(o['name'])}</b> <span class='mono small'>{esc(cid)}</span></div>"
           f"<div class='mrow'>스캐너 top1 → <b>{esc(t1.get('name','—'))}</b> <span class='sc'>{esc(t1.get('score',''))}</span> <span class='mono small'>{esc(t1.get('id','—'))}</span></div>"
           f"<div class='t5wrap'>{t5_html(s,cid)}</div>")
    return (f"<div class='card' data-id='{esc(cid)}' data-status='{esc(r['status'])}' data-set='{esc(o['set'] or '')}'>"
            f"<div class='hd'><span class='badge' style='background:{sc}'>{esc(r['status'])}</span>"
            f"<span class='cno'>{esc(o['name'])} · {esc(o['set'])} {esc(o['num'])} · {esc(o['rarity'])}</span><span class='conf'>{esc(cid)}</span></div>"
            f"<div class='body'><div class='col'><div class='lbl'>우리 카드</div>"
            f"<img class='big' loading='lazy' src='scanner/data/{esc(o['img'])}' onerror=\"this.style.opacity=.12\">"
            f"<div class='meta'><b>{esc(o['name'])}</b><br><span class='mono'>{esc(o['jp_ref'])}</span> · {esc(o['rarity'])}</div></div>"
            f"<div class='col'><div class='lbl'>SNKRDUNK 후보</div>{right}</div>"
            f"<div class='col'><div class='lbl'>교차검증</div>{cross}"
            f"<div class='judge'><button data-j='match'>✓ 매칭</button><button data-j='no'>✗ 아님</button><button data-j='hold'>? 보류</button><span class='jstate'></span></div></div></div></div>")

def mini_card(r):
    o=r["our"]
    return (f"<div class='mini' data-status='{esc(r['status'])}' data-set='{esc(o['set'] or 'NO_JP')}'>"
            f"<img loading='lazy' src='scanner/data/{esc(o['img'])}' onerror=\"this.style.opacity=.12\">"
            f"<div class='mm'><b>{esc(o['name'])}</b><br><span class='mono'>{esc(o['jp_ref'] or 'NO_JP')}</span><br>"
            f"<span class='mrar'>{esc(o['set'] or '—')} {esc(o['num'])} · {esc(o['rarity'])}</span></div></div>")

def only_card(r):
    a=r["snk"]; s=r["scan"]; snk_img=f"scanner/data/{s['img']}" if s and s.get("img") else ""
    return (f"<div class='card only'><div class='hd'><span class='badge' style='background:{SC['SNKRDUNK_ONLY']}'>SNKRDUNK_ONLY</span>"
            f"<span class='cno'>{esc(a.get('set',''))} {esc(a.get('number',''))} · {esc(a.get('rarity',''))}</span><span class='conf'>우리 DB 미보유</span></div>"
            f"<div class='body'><div class='col'><div class='lbl'>우리 카드</div><div class='nomatch'>미보유</div></div>"
            f"<div class='col'><div class='lbl'>SNKRDUNK</div><img class='big' loading='lazy' src='{esc(snk_img)}' onerror=\"this.style.opacity=.12\">"
            f"<div class='meta'><b>{esc(a.get('jp_title',''))}</b><br><span class='mono'>{esc(a.get('product_number',''))}</span><br>"
            f"<a href='{esc(a.get('detail_url',''))}' target='_blank'>▶ {esc(a.get('detail_url',''))}</a></div>{sold_html(s)}</div>"
            f"<div class='col'><div class='lbl'>스캐너 참고</div><div class='t5wrap'>{t5_html(s,None)}</div></div></div></div>")

CAND_ORDER={"CONFLICT":0,"SNK_IMAGE_MISSING":1,"TEXT_MATCH_ONLY":2,"HIGH_CONFIDENCE":3}
with_cand=[r for r in rows if r["snk"]]
no_cand=[r for r in rows if not r["snk"]]
with_cand.sort(key=lambda r:(CAND_ORDER.get(r["status"],9), r["our"]["set"] or "", r["our"]["num_int"] or 0))
no_cand.sort(key=lambda r:(r["our"]["set"] or "zzz", r["our"]["num_int"] or 0))
sets_in_nocand=sorted({(r["our"]["set"] or "NO_JP") for r in no_cand})

JS = """
const J=JSON.parse(localStorage.getItem('snk_all')||'{}');
function paint(el){const id=el.dataset.id,v=J[id],s=el.querySelector('.jstate');if(!s)return;
  el.querySelectorAll('.judge button').forEach(b=>b.classList.toggle('on',b.dataset.j===v));
  s.textContent=v?('판정: '+({match:'✓',no:'✗',hold:'?'}[v])):'';}
document.querySelectorAll('#cand .card').forEach(el=>{paint(el);
  el.querySelectorAll('.judge button').forEach(b=>{b.onclick=()=>{J[el.dataset.id]=b.dataset.j;
    localStorage.setItem('snk_all',JSON.stringify(J));paint(el);upd();};});});
function upd(){document.getElementById('jcount').textContent=Object.keys(J).length;}
function fc(){const st=document.getElementById('fstatus').value,u=document.getElementById('funj').checked;
  document.querySelectorAll('#cand .card').forEach(el=>{let ok=true;if(st&&el.dataset.status!==st)ok=false;
    if(u&&J[el.dataset.id])ok=false;el.style.display=ok?'':'none';});}
function fm(){const s=document.getElementById('fset').value;
  document.querySelectorAll('#nocand .mini').forEach(el=>{el.style.display=(!s||el.dataset.set===s)?'':'none';});}
document.getElementById('fstatus').onchange=fc;document.getElementById('funj').onchange=fc;
document.getElementById('fset').onchange=fm;
document.getElementById('expt').onclick=()=>{let o='our_card_id,verdict\\n';for(const k in J)o+=k+','+J[k]+'\\n';
  const b=new Blob([o],{type:'text/csv'}),a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='snkrdunk_ourcard_all_verdicts.csv';a.click();};
upd();
"""
setopts="".join(f"<option>{esc(s)}</option>" for s in sets_in_nocand)
statline=(f"전체 {len(rows)} · SNK매칭 {matched} · scanner {scanned} · HIGH {stat.get('HIGH_CONFIDENCE',0)} · "
          f"CONFLICT {stat.get('CONFLICT',0)} · NOT_IN_CSV {stat.get('SNK_ID_NOT_IN_CSV',0)} · "
          f"NO_JP_REF {stat.get('NO_JP_REF',0)} · SNKRDUNK_ONLY {len(only_rows)}")
page=f"""<!doctype html><html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>SNKRDUNK 검수 · 우리 전체카드</title><style>
*{{box-sizing:border-box}}body{{font-family:-apple-system,'Apple SD Gothic Neo',sans-serif;margin:0;background:#f6f8fa;color:#1f2328}}
.top{{position:sticky;top:0;background:#24292f;color:#fff;padding:10px 16px;z-index:10;display:flex;gap:12px;align-items:center;flex-wrap:wrap}}
.top b{{font-size:15px}}.top .stat{{font-size:12px;opacity:.85}}.top select,.top label{{font-size:13px}}
.top button{{padding:5px 12px;border:0;border-radius:6px;background:#2da44e;color:#fff;cursor:pointer}}
.wrap{{max-width:1120px;margin:0 auto;padding:14px}}
h2.sec{{margin:24px 4px 8px;padding-top:10px;border-top:2px solid #d0d7de;font-size:15px}}
.card{{background:#fff;border:1px solid #d0d7de;border-radius:10px;margin:12px 0;overflow:hidden}}.card.only{{background:#faf8ff}}
.hd{{display:flex;gap:10px;align-items:center;padding:8px 12px;border-bottom:1px solid #eaeef2;background:#fafbfc}}
.badge{{color:#fff;font-size:11px;font-weight:700;padding:3px 8px;border-radius:20px}}
.cno{{font-weight:700}}.conf{{font-size:11px;color:#57606a;margin-left:auto;font-family:ui-monospace,monospace}}
.body{{display:grid;grid-template-columns:1fr 1fr 1.3fr;gap:10px;padding:12px}}@media(max-width:820px){{.body{{grid-template-columns:1fr}}}}
.lbl{{font-size:11px;font-weight:700;color:#57606a;text-transform:uppercase;margin-bottom:6px}}
.big{{width:100%;max-width:230px;border-radius:8px;background:#f0f0f0;display:block}}
.meta{{font-size:13px;margin-top:6px;line-height:1.5}}.mono{{font-family:ui-monospace,monospace;font-size:11px;color:#57606a}}.small{{font-size:10px}}
a{{color:#0969da;word-break:break-all;font-size:12px}}.nomatch{{color:#8b949e;font-size:13px;padding:18px 0;font-style:italic}}
.sold{{margin-top:6px;font-size:12px;background:#fff8e5;border:1px solid #f0d58c;padding:5px 8px;border-radius:6px}}
.mrow{{font-size:13px;margin:3px 0}}.sc{{color:#1a7f37;font-weight:700}}.rar{{color:#8250df;font-size:11px}}.ref{{font-family:ui-monospace,monospace;font-size:10px;color:#57606a}}
.t5wrap{{display:flex;gap:6px;flex-wrap:wrap;margin:8px 0;padding:8px;background:#f6f8fa;border-radius:8px}}
.t5{{width:74px;font-size:10px;text-align:center}}.t5 img{{width:70px;height:96px;object-fit:cover;border-radius:4px;border:2px solid transparent}}
.t5hit img{{border-color:#1a7f37}}.t5m{{line-height:1.3;margin-top:2px}}
.judge{{margin-top:10px;display:flex;gap:8px;align-items:center}}.judge button{{padding:7px 14px;border:1px solid #d0d7de;border-radius:7px;background:#fff;cursor:pointer;font-size:14px}}
.judge button.on{{background:#0969da;color:#fff;border-color:#0969da}}.jstate{{font-size:12px;color:#57606a}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}}
.mini{{background:#fff;border:1px solid #d8dee4;border-radius:8px;padding:8px;font-size:12px}}
.mini img{{width:100%;border-radius:6px;background:#f0f0f0}}.mini .mm{{margin-top:5px;line-height:1.4}}.mrar{{color:#57606a;font-size:11px}}
.note{{font-size:12px;color:#57606a;margin:4px}}
</style></head><body>
<div class="top"><b>SNKRDUNK 검수 · 우리 전체카드</b><span class="stat">{esc(statline)}</span>
  <label>후보상태 <select id="fstatus"><option value="">전체</option><option>CONFLICT</option><option>SNK_IMAGE_MISSING</option>
    <option>TEXT_MATCH_ONLY</option><option>HIGH_CONFIDENCE</option></select></label>
  <label><input type="checkbox" id="funj"> 미판정만</label>
  <span class="stat">판정 <b id="jcount">0</b></span><button id="expt">CSV 내보내기</button></div>
<div class="wrap">
  <h2 class="sec">① 우리 카드 — SNKRDUNK 직접후보 보유 ({len(with_cand)}장) · 검수대상</h2>
  <div class="note">텍스트(set+번호) ∩ 스캐너(top5) 교차검증. ★ = 스캐너 후보가 텍스트매칭 카드와 동일.</div>
  <div id="cand">{''.join(full_card(r) for r in with_cand)}</div>
  <h2 class="sec">② 우리 카드 — SNK ID 미매칭 ({len(no_cand)}장)</h2>
  <div class="note">SNK_ID_NOT_IN_CSV=기존 SNK CSV에 대응 id 없음 · NO_JP_REF=우리 카드에 jp_scrydex_ref 없음. 추후 그 세트 CSV가 채워지면 ①로 이동.</div>
  <label class="note">세트 필터 <select id="fset"><option value="">전체</option>{setopts}</select></label>
  <div id="nocand" class="grid">{''.join(mini_card(r) for r in no_cand)}</div>
  <h2 class="sec">③ SNKRDUNK only / 우리 DB 미보유 ({only_total}장 중 {len(only_rows)} 표시·캡)</h2>
  <div id="only">{''.join(only_card(r) for r in only_rows)}</div>
</div><script>{JS}</script></body></html>"""
with open(args.out_html, "w", encoding="utf-8") as f:
    f.write(page)
print(f"[HTML] {args.out_html}")
