#!/usr/bin/env python3
"""SNKRDUNK M3 검수툴 — **우리 카드 기준** (axis flip).

메인: 우리 catalog M3 카드 전부 (1 우리카드 = 1 row). 왼쪽=우리카드(항상표시), 오른쪽=SNKRDUNK 후보 or NOT_FOUND.
별도섹션: SNKRDUNK엔 있고 우리 DB엔 없는 카드(트레이너/스타디움 등) = SNKRDUNK_ONLY.

매칭: 텍스트(M3+카드번호) ∩ 스캐너(우리 DINOv2+FAISS가 SNKRDUNK 이미지를 인식한 top1).
출력: snkrdunk_ourcard_review_m3.csv + snkrdunk_ourcard_review_m3.html
read-only: prod DB write 0, raw 가격 적재 0.
"""
import csv, os, re, json, time, statistics, html, urllib.request, urllib.parse
from collections import Counter
from PIL import Image

ROOT = "/Users/fury/pokemon-card-app"
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
SNK_DIR = "/Users/fury/Downloads/price_v8_snkrdunk"
APPAREL_CSV = f"{SNK_DIR}/snkrdunk_apparel_catalog_scanned.csv"
SALES_CSV = f"{SNK_DIR}/snkrdunk_recent_sales_by_apparel.csv"
IMG_OUT = f"{ROOT}/scanner/data/snktest_m3"
IMG_REL = "snktest_m3"
CSV_OUT = f"{ROOT}/python/price_v8/snkrdunk_ourcard_review_m3.csv"
HTML_OUT = f"{ROOT}/snkrdunk_ourcard_review_m3.html"
SCANNER = "http://localhost:8082/identify_path"
SCAN_CONFIDENT = 0.55
SET = "M3"
SET_REF = "m3_ja"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
os.makedirs(IMG_OUT, exist_ok=True)

def num_int(s):
    if not s: return None
    m = re.search(r"(\d+)", str(s).split("/")[0].split("-")[-1])
    return int(m.group(1)) if m else None

def our_img_rel(cid):
    for suf in ("_jp", "_ko", "_en"):
        if os.path.exists(f"{ROOT}/scanner/data/cards/{cid}{suf}.png"):
            return f"cards/{cid}{suf}.png"
    return ""

# ---- 우리 catalog (이 세트) ----
our_cards = []
with open(CATALOG, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        ref = (row.get("jp_scrydex_ref") or "").strip()
        if not re.match(rf"^{SET_REF}-\d+$", ref):
            continue
        our_cards.append({
            "card_id": row["card_id"], "name": row["name"],
            "code": row["official_card_code"], "num": row["collection_number"],
            "num_int": num_int(ref.split("-")[-1]), "rarity": row["rarity_code"],
            "jp_ref": ref, "img": our_img_rel(row["card_id"]),
        })
our_by_num = {c["num_int"]: c for c in our_cards}
print(f"[우리 catalog {SET}] {len(our_cards)}장")

# ---- SNKRDUNK apparels (이 세트) ----
apparels = []
with open(APPAREL_CSV, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        if (row.get("set") or "").upper() != SET:
            continue
        row["_num"] = num_int(row.get("number") or row.get("product_number"))
        apparels.append(row)
print(f"[SNKRDUNK {SET}] {len(apparels)}개")

# ---- sold 집계 ----
sales = {}
if os.path.exists(SALES_CSV):
    tmp = {}
    with open(SALES_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            try: p = int(float(row["price_jpy"]))
            except: continue
            tmp.setdefault(row["apparel_id"], []).append((p, row.get("sold_date", "")))
    for aid, v in tmp.items():
        ps = [p for p, _ in v]
        sales[aid] = {"count": len(ps), "median": int(statistics.median(ps)),
                      "min": min(ps), "max": max(ps),
                      "latest": max((d for _, d in v if d), default="")}

# ---- 이미지 다운로드 + 스캐너 ----
def fetch_png(aid, url):
    png = f"{IMG_OUT}/{aid}.png"
    if os.path.exists(png) and os.path.getsize(png) > 1000:
        return png
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

# 각 apparel 1회 스캔 → 결과 캐시
snk_scan = {}
for i, ap in enumerate(apparels, 1):
    aid = ap["apparel_id"]
    png = fetch_png(aid, ap.get("image_url", ""))
    rel = f"{IMG_REL}/{aid}.png" if png else None
    top1 = {}; top5 = []; note = "no_image"
    if rel:
        data, note = scan(rel)
        if data:
            tr = data["topResult"]
            top1 = {"id": tr["cardId"], "name": tr["name"], "rarity": tr.get("rarityCode", ""),
                    "ref": tr.get("scrydexRef", ""), "score": round(float(tr["score"]), 4)}
            for c in data.get("candidates", [])[:5]:
                top5.append({"cardId": c["cardId"], "name": c["name"], "rarity": c.get("rarityCode", ""),
                             "ref": c.get("scrydexRef", ""), "score": round(float(c["score"]), 4)})
    snk_scan[aid] = {"ap": ap, "img": rel, "top1": top1, "top5": top5, "note": note,
                     "sold": sales.get(aid)}
    print(f"[{i}/{len(apparels)}] {aid} {ap.get('product_number','')} scan={top1.get('score')} {top1.get('name','')}")

# ---- 메인: 우리 카드 기준 ----
def classify(our_id, top1):
    has_scan = bool(top1) and top1.get("score") is not None
    conf = has_scan and top1["score"] >= SCAN_CONFIDENT
    if has_scan and top1["id"] == our_id:
        return "HIGH_CONFIDENCE", "HIGH"
    if conf and top1["id"] != our_id:
        return "CONFLICT", "REVIEW"
    return "TEXT_MATCH_ONLY", "MED"   # 번호는 매칭됐으나 스캐너 약함/불일치-비신뢰

rows = []           # 메인(우리카드) 행
for c in sorted(our_cards, key=lambda x: x["num_int"]):
    ap = next((a for a in apparels if a["_num"] == c["num_int"]), None)
    if not ap:
        rows.append({"_kind": "main", "our": c, "snk": None, "scan": None,
                     "match_status": "NOT_FOUND", "confidence": "LOW", "notes": "SNKRDUNK 후보 없음"})
        continue
    s = snk_scan[ap["apparel_id"]]
    st, cf = classify(c["card_id"], s["top1"])
    rows.append({"_kind": "main", "our": c, "snk": ap, "scan": s,
                 "match_status": st, "confidence": cf, "notes": s["note"] or ""})

# ---- 별도: SNKRDUNK only (우리 미보유) ----
only_rows = []
for ap in sorted(apparels, key=lambda x: (x["_num"] or 0)):
    if ap["_num"] in our_by_num:
        continue
    s = snk_scan[ap["apparel_id"]]
    only_rows.append({"_kind": "only", "our": None, "snk": ap, "scan": s,
                      "match_status": "SNKRDUNK_ONLY", "confidence": "—", "notes": s["note"] or ""})

# ---- CSV ----
COLS = ["our_card_id","our_name","our_jp_ref","our_set_code","our_card_no","our_rarity","our_image_path",
        "snkrdunk_id","snkrdunk_url","snkrdunk_title","snkrdunk_product_number","snkrdunk_image_url",
        "scanner_top1_card_id","scanner_top1_name","scanner_top1_score","scanner_top5_json",
        "text_match_card_id","match_status","confidence","notes"]
def to_csv_row(r):
    o = r["our"] or {}; ap = r["snk"] or {}; s = r["scan"] or {}
    t1 = (s.get("top1") or {})
    return {
        "our_card_id": o.get("card_id",""), "our_name": o.get("name",""), "our_jp_ref": o.get("jp_ref",""),
        "our_set_code": SET, "our_card_no": o.get("num",""), "our_rarity": o.get("rarity",""),
        "our_image_path": o.get("img",""),
        "snkrdunk_id": ap.get("apparel_id",""), "snkrdunk_url": ap.get("detail_url",""),
        "snkrdunk_title": ap.get("jp_title",""), "snkrdunk_product_number": ap.get("product_number",""),
        "snkrdunk_image_url": ap.get("image_url",""),
        "scanner_top1_card_id": t1.get("id",""), "scanner_top1_name": t1.get("name",""),
        "scanner_top1_score": t1.get("score",""),
        "scanner_top5_json": json.dumps(s.get("top5",[]), ensure_ascii=False),
        "text_match_card_id": o.get("card_id","") if r["_kind"]=="main" and r["snk"] else "",
        "match_status": r["match_status"], "confidence": r["confidence"], "notes": r["notes"],
    }
with open(CSV_OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=COLS); w.writeheader()
    for r in rows + only_rows:
        w.writerow(to_csv_row(r))
print(f"\n[CSV] {CSV_OUT}")

# ---- 통계 ----
main_stat = Counter(r["match_status"] for r in rows)
matched = sum(1 for r in rows if r["snk"])
print(f"[통계] 우리 {SET} {len(rows)}장 / SNKRDUNK 후보보유 {matched} / "
      f"HIGH {main_stat.get('HIGH_CONFIDENCE',0)} / CONFLICT {main_stat.get('CONFLICT',0)} / "
      f"TEXT_ONLY {main_stat.get('TEXT_MATCH_ONLY',0)} / NOT_FOUND {main_stat.get('NOT_FOUND',0)} / "
      f"SNKRDUNK_ONLY {len(only_rows)}")

# ---- HTML ----
def esc(s): return html.escape(str(s if s is not None else ""))
SC = {"HIGH_CONFIDENCE":"#1a7f37","CONFLICT":"#cf222e","TEXT_MATCH_ONLY":"#9a6700",
      "NOT_FOUND":"#6e7781","SNKRDUNK_ONLY":"#8250df"}
PRIORITY = {"CONFLICT":0,"TEXT_MATCH_ONLY":1,"HIGH_CONFIDENCE":2,"NOT_FOUND":3}

def top5_html(s, our_id):
    if not s or not s.get("top5"): return "<i>스캐너 결과 없음</i>"
    out = []
    for j, c in enumerate(s["top5"]):
        hit = "★" if c["cardId"] == our_id else ""
        cimg = f"scanner/data/cards/{c['cardId']}_jp.png"
        out.append(f"<div class='t5{' t5hit' if hit else ''}'><img loading='lazy' src='{esc(cimg)}' "
                   f"onerror=\"this.style.opacity=.12\"><div class='t5m'><b>{j+1}.{hit}</b> {esc(c['name'])} "
                   f"<span class='rar'>{esc(c['rarity'])}</span><br><span class='ref'>{esc(c['ref'])}</span> "
                   f"· <span class='sc'>{c['score']}</span></div></div>")
    return "".join(out)

def sold_html(s):
    so = s and s.get("sold")
    if not so: return ""
    return (f"<div class='sold'>💴 sold {so['count']}건 · median <b>¥{so['median']:,}</b> "
            f"(¥{so['min']:,}~¥{so['max']:,}) · 최근 {esc(so['latest'])}</div>")

def main_card_html(r):
    o = r["our"]; ap = r["snk"]; s = r["scan"]
    cid = o["card_id"]; sc = SC.get(r["match_status"], "#333")
    our_img = f"scanner/data/{o['img']}" if o["img"] else ""
    if ap:
        snk_img = f"scanner/data/{s['img']}" if s and s.get("img") else ""
        t1 = (s.get("top1") or {}) if s else {}
        right = f"""<img class="big" loading="lazy" src="{esc(snk_img)}" onerror="this.style.opacity=.12">
        <div class="meta"><b>{esc(ap.get('jp_title',''))}</b><br>
          <span class="mono">{esc(ap.get('product_number',''))}</span> · {esc(ap.get('rarity',''))}<br>
          <a href="{esc(ap.get('detail_url',''))}" target="_blank">▶ {esc(ap.get('detail_url',''))}</a></div>
        {sold_html(s)}"""
        cross = f"""<div class="mrow">텍스트(M3+번호) → <b>{esc(o['name'])}</b> <span class="mono small">{esc(cid)}</span></div>
        <div class="mrow">스캐너 top1 → <b>{esc(t1.get('name','—'))}</b> <span class="sc">{esc(t1.get('score',''))}</span>
          <span class="mono small">{esc(t1.get('id','—'))}</span></div>
        <div class="t5wrap">{top5_html(s, cid)}</div>"""
    else:
        right = "<div class='nomatch'>SNKRDUNK 후보 없음 (NOT_FOUND)</div>"
        cross = "<div class='nomatch'>—</div>"
    return f"""<div class="card" data-id="{esc(cid)}" data-status="{esc(r['match_status'])}">
  <div class="hd"><span class="badge" style="background:{sc}">{esc(r['match_status'])}</span>
    <span class="cno">{esc(o['name'])} · M3 {esc(o['num'])} · {esc(o['rarity'])}</span>
    <span class="conf">{esc(cid)}</span></div>
  <div class="body">
    <div class="col"><div class="lbl">우리 카드</div>
      <img class="big" loading="lazy" src="{esc(our_img)}" onerror="this.style.opacity=.12">
      <div class="meta"><b>{esc(o['name'])}</b><br><span class="mono">{esc(o['jp_ref'])}</span> · {esc(o['rarity'])}</div></div>
    <div class="col"><div class="lbl">SNKRDUNK 후보</div>{right}</div>
    <div class="col"><div class="lbl">교차검증</div>{cross}
      <div class="judge"><button data-j="match">✓ 매칭</button><button data-j="no">✗ 아님</button>
        <button data-j="hold">? 보류</button><span class="jstate"></span></div></div>
  </div></div>"""

def only_card_html(r):
    ap = r["snk"]; s = r["scan"]; aid = ap["apparel_id"]
    snk_img = f"scanner/data/{s['img']}" if s and s.get("img") else ""
    return f"""<div class="card only" data-id="only_{esc(aid)}" data-status="SNKRDUNK_ONLY">
  <div class="hd"><span class="badge" style="background:{SC['SNKRDUNK_ONLY']}">SNKRDUNK_ONLY</span>
    <span class="cno">M3 {esc(ap.get('number',''))} · {esc(ap.get('rarity',''))}</span>
    <span class="conf">우리 DB 미보유</span></div>
  <div class="body">
    <div class="col"><div class="lbl">우리 카드</div><div class="nomatch">해당 없음 (미보유)</div></div>
    <div class="col"><div class="lbl">SNKRDUNK</div>
      <img class="big" loading="lazy" src="{esc(snk_img)}" onerror="this.style.opacity=.12">
      <div class="meta"><b>{esc(ap.get('jp_title',''))}</b><br><span class="mono">{esc(ap.get('product_number',''))}</span><br>
        <a href="{esc(ap.get('detail_url',''))}" target="_blank">▶ {esc(ap.get('detail_url',''))}</a></div>{sold_html(s)}</div>
    <div class="col"><div class="lbl">스캐너 참고(미보유라 정답 없음)</div><div class="t5wrap">{top5_html(s, None)}</div></div>
  </div></div>"""

main_sorted = sorted(rows, key=lambda r: (PRIORITY.get(r["match_status"], 9), r["our"]["num_int"]))
main_html = "".join(main_card_html(r) for r in main_sorted)
only_html = "".join(only_card_html(r) for r in only_rows)

JS = """
const J=JSON.parse(localStorage.getItem('snk_oc_m3')||'{}');
function paint(el){const id=el.dataset.id,v=J[id],s=el.querySelector('.jstate');if(!s)return;
  el.querySelectorAll('.judge button').forEach(b=>b.classList.toggle('on',b.dataset.j===v));
  s.textContent=v?('판정: '+({match:'✓ 매칭',no:'✗ 아님',hold:'? 보류'}[v])):'';}
document.querySelectorAll('.card').forEach(el=>{paint(el);
  el.querySelectorAll('.judge button').forEach(b=>{b.onclick=()=>{J[el.dataset.id]=b.dataset.j;
    localStorage.setItem('snk_oc_m3',JSON.stringify(J));paint(el);upd();};});});
function upd(){document.getElementById('jcount').textContent=Object.keys(J).length;}
function flt(){const st=document.getElementById('fstatus').value,u=document.getElementById('funjudged').checked;
  document.querySelectorAll('#main .card').forEach(el=>{let ok=true;
    if(st&&el.dataset.status!==st)ok=false;if(u&&J[el.dataset.id])ok=false;el.style.display=ok?'':'none';});}
function expt(){let o='our_card_id,verdict\\n';for(const k in J)o+=k+','+J[k]+'\\n';
  const b=new Blob([o],{type:'text/csv'}),a=document.createElement('a');
  a.href=URL.createObjectURL(b);a.download='snkrdunk_ourcard_m3_verdicts.csv';a.click();}
document.getElementById('fstatus').onchange=flt;document.getElementById('funjudged').onchange=flt;
document.getElementById('expt').onclick=expt;upd();
"""

statline = (f"우리 M3 {len(rows)}장 · 후보보유 {matched} · "
            f"HIGH {main_stat.get('HIGH_CONFIDENCE',0)} · CONFLICT {main_stat.get('CONFLICT',0)} · "
            f"TEXT_ONLY {main_stat.get('TEXT_MATCH_ONLY',0)} · NOT_FOUND {main_stat.get('NOT_FOUND',0)} · "
            f"SNKRDUNK_ONLY {len(only_rows)}")
page = f"""<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>SNKRDUNK M3 검수 (우리카드 기준)</title>
<style>
*{{box-sizing:border-box}}body{{font-family:-apple-system,'Apple SD Gothic Neo',sans-serif;margin:0;background:#f6f8fa;color:#1f2328}}
.top{{position:sticky;top:0;background:#24292f;color:#fff;padding:12px 16px;z-index:10;display:flex;gap:14px;align-items:center;flex-wrap:wrap}}
.top b{{font-size:16px}}.top .stat{{font-size:12px;opacity:.85}}.top select,.top label{{font-size:13px}}
.top button{{padding:5px 12px;border:0;border-radius:6px;background:#2da44e;color:#fff;cursor:pointer}}
.wrap{{max-width:1100px;margin:0 auto;padding:14px}}
h2.sec{{margin:26px 4px 6px;padding-top:10px;border-top:2px solid #d0d7de;font-size:15px}}
.card{{background:#fff;border:1px solid #d0d7de;border-radius:10px;margin:12px 0;overflow:hidden}}
.card.only{{background:#faf8ff}}
.hd{{display:flex;gap:10px;align-items:center;padding:8px 12px;border-bottom:1px solid #eaeef2;background:#fafbfc}}
.badge{{color:#fff;font-size:11px;font-weight:700;padding:3px 8px;border-radius:20px}}
.cno{{font-weight:700}}.conf{{font-size:11px;color:#57606a;margin-left:auto;font-family:ui-monospace,monospace}}
.body{{display:grid;grid-template-columns:1fr 1fr 1.3fr;gap:10px;padding:12px}}
@media(max-width:820px){{.body{{grid-template-columns:1fr}}}}
.col{{min-width:0}}.lbl{{font-size:11px;font-weight:700;color:#57606a;text-transform:uppercase;margin-bottom:6px}}
.big{{width:100%;max-width:230px;border-radius:8px;background:#f0f0f0;display:block}}
.meta{{font-size:13px;margin-top:6px;line-height:1.5}}.mono{{font-family:ui-monospace,monospace;font-size:11px;color:#57606a}}
.small{{font-size:10px}}a{{color:#0969da;word-break:break-all;font-size:12px}}
.nomatch{{color:#8b949e;font-size:13px;padding:20px 0;font-style:italic}}
.sold{{margin-top:6px;font-size:12px;background:#fff8e5;border:1px solid #f0d58c;padding:5px 8px;border-radius:6px}}
.mrow{{font-size:13px;margin:3px 0}}.sc{{color:#1a7f37;font-weight:700}}.rar{{color:#8250df;font-size:11px}}
.ref{{font-family:ui-monospace,monospace;font-size:10px;color:#57606a}}
.t5wrap{{display:flex;gap:6px;flex-wrap:wrap;margin:8px 0;padding:8px;background:#f6f8fa;border-radius:8px}}
.t5{{width:74px;font-size:10px;text-align:center}}.t5 img{{width:70px;height:96px;object-fit:cover;border-radius:4px;border:2px solid transparent}}
.t5hit img{{border-color:#1a7f37}}.t5m{{line-height:1.3;margin-top:2px}}
.judge{{margin-top:10px;display:flex;gap:8px;align-items:center}}
.judge button{{padding:7px 14px;border:1px solid #d0d7de;border-radius:7px;background:#fff;cursor:pointer;font-size:14px}}
.judge button.on{{background:#0969da;color:#fff;border-color:#0969da}}.jstate{{font-size:12px;color:#57606a}}
</style></head><body>
<div class="top"><b>SNKRDUNK M3 검수 · 우리카드 기준</b><span class="stat">{esc(statline)}</span>
  <label>상태 <select id="fstatus"><option value="">전체</option>
    <option>CONFLICT</option><option>TEXT_MATCH_ONLY</option><option>HIGH_CONFIDENCE</option><option>NOT_FOUND</option></select></label>
  <label><input type="checkbox" id="funjudged"> 미판정만</label>
  <span class="stat">판정 <b id="jcount">0</b></span><button id="expt">CSV 내보내기</button></div>
<div class="wrap">
  <h2 class="sec">① 우리 M3 카드 기준 검수 ({len(rows)}장)</h2>
  <div id="main">{main_html}</div>
  <h2 class="sec">② SNKRDUNK only / 우리 DB 미보유 ({len(only_rows)}장)</h2>
  <div id="only">{only_html}</div>
</div>
<script>{JS}</script></body></html>"""
with open(HTML_OUT, "w", encoding="utf-8") as f:
    f.write(page)
print(f"[HTML] {HTML_OUT}")
