#!/usr/bin/env python3
"""SNKRDUNK M3 end-to-end: ID 수집(이미 스캔됨) -> 이미지 다운로드 -> 스캐너 교차매칭 -> CSV + 검수 HTML.

흐름:
 1. 우리 카탈로그 M3 카드 로드 (jp_scrydex_ref m3_ja-N, collection_number NNN/080)
 2. SNKRDUNK M3 apparels 로드 (snkrdunk_apparel_catalog_scanned.csv: apparel_id/product_number/image_url ...)
 3. SNKRDUNK 이미지 다운로드(webp) -> png 변환 (scanner/data/snktest_m3/)
 4. 우리 스캐너(DINOv2+FAISS) /identify_path 로 각 SNKRDUNK 이미지 top5
 5. 텍스트매칭(M3 + 카드번호) vs 스캐너매칭 교차검증 -> match_status
 6. snkrdunk_scanner_match_candidates_m3.csv + snkrdunk_scanner_review_m3.html

read-only: prod DB write 0, raw 가격 적재 0. 확정 검수만 나중에 승격.
"""
import csv, os, re, json, time, statistics, html, urllib.request, urllib.parse, sys
from PIL import Image

ROOT = "/Users/fury/pokemon-card-app"
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
SNK_DIR = "/Users/fury/Downloads/price_v8_snkrdunk"
APPAREL_CSV = f"{SNK_DIR}/snkrdunk_apparel_catalog_scanned.csv"
SALES_CSV = f"{SNK_DIR}/snkrdunk_recent_sales_by_apparel.csv"
IMG_OUT = f"{ROOT}/scanner/data/snktest_m3"          # 스캐너 data 기준 상대경로 = snktest_m3/{aid}.png
IMG_REL_FOR_SCANNER = "snktest_m3"                    # identify_path?path= 용 (scanner/data/ 기준)
CSV_OUT = f"{ROOT}/python/price_v8/snkrdunk_scanner_match_candidates_m3.csv"
HTML_OUT = f"{ROOT}/snkrdunk_scanner_review_m3.html"
SCANNER = "http://localhost:8082/identify_path"
SCAN_CONFIDENT = 0.55   # 스캐너 top1 신뢰 임계 (자기검증 1.0, cross-source 메가픽시 0.793 기준)
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

os.makedirs(IMG_OUT, exist_ok=True)

def num_int(s):
    """'114/080' or '114' or 'pkmn-tcg-M3-114' -> 114 (int) or None"""
    if not s:
        return None
    m = re.search(r"(\d+)", str(s).split("/")[0].split("-")[-1])
    return int(m.group(1)) if m else None

# ---- 1. 카탈로그 M3 인덱스 (번호 -> 카드) ----
catalog_by_num = {}
m3_cards = []
with open(CATALOG, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        ref = (row.get("jp_scrydex_ref") or "").strip()
        if not re.match(r"^m3_ja-\d+$", ref):
            continue
        n = num_int(ref.split("-")[-1])
        rec = {
            "card_id": row["card_id"], "name": row["name"],
            "code": row["official_card_code"], "num": row["collection_number"],
            "num_int": n, "rarity": row["rarity_code"], "jp_ref": ref,
            "img_jp": f"cards/{row['card_id']}_jp.png",
        }
        m3_cards.append(rec)
        catalog_by_num[n] = rec
print(f"[1] 카탈로그 M3 카드: {len(m3_cards)}장 (번호 인덱스 {len(catalog_by_num)})")

# 우리 카드 이미지 실제 존재여부
for c in m3_cards:
    c["img_exists"] = os.path.exists(f"{ROOT}/scanner/data/{c['img_jp']}")

# ---- 2. SNKRDUNK M3 apparels ----
apparels = []
with open(APPAREL_CSV, encoding="utf-8") as f:
    for row in csv.DictReader(f):
        if (row.get("set") or "").upper() != "M3":
            continue
        apparels.append(row)
print(f"[2] SNKRDUNK M3 apparels: {len(apparels)}개")

# ---- 3. sold 집계 (apparel_id -> {count, median, latest}) ----
sales = {}
if os.path.exists(SALES_CSV):
    tmp = {}
    with open(SALES_CSV, encoding="utf-8") as f:
        for row in csv.DictReader(f):
            aid = row["apparel_id"]
            try:
                p = int(float(row["price_jpy"]))
            except Exception:
                continue
            tmp.setdefault(aid, {"prices": [], "dates": []})
            tmp[aid]["prices"].append(p)
            tmp[aid]["dates"].append(row.get("sold_date", ""))
    for aid, v in tmp.items():
        sales[aid] = {
            "count": len(v["prices"]),
            "median": int(statistics.median(v["prices"])),
            "min": min(v["prices"]), "max": max(v["prices"]),
            "latest": max(d for d in v["dates"] if d) if any(v["dates"]) else "",
        }
print(f"[3] sold 보유 apparel: {len(sales)}개")

# ---- 4. 이미지 다운로드 + 변환 ----
def fetch_png(aid, url):
    png = f"{IMG_OUT}/{aid}.png"
    if os.path.exists(png) and os.path.getsize(png) > 1000:
        return png
    if not url:
        return None
    raw = f"{IMG_OUT}/{aid}.src"
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=30) as r:
            data = r.read()
        with open(raw, "wb") as out:
            out.write(data)
        Image.open(raw).convert("RGB").save(png, "PNG")
        os.remove(raw)
        time.sleep(0.4)  # 정중한 rate-limit
        return png
    except Exception as e:
        print(f"   [img fail] {aid}: {e}")
        return None

# ---- 5. 스캐너 호출 ----
def scan(rel_png):
    path = urllib.parse.quote(rel_png)
    try:
        with urllib.request.urlopen(f"{SCANNER}?path={path}", timeout=60) as r:
            d = json.load(r)
    except Exception as e:
        return None, str(e)
    # 스캐너 status: success | low_confidence | error. low_confidence도 유효한 top5 보유
    # (자체 임계 미달일 뿐) — 점수는 그대로 받고 cross-check + SCAN_CONFIDENT로 우리가 판정.
    st = d.get("status")
    if st in ("success", "low_confidence") and d.get("data", {}).get("topResult"):
        data = d["data"]
        data["_scan_status"] = st
        return data, ("low_confidence" if st == "low_confidence" else None)
    return None, d.get("message", f"scan error ({st})")

rows = []
for i, ap in enumerate(apparels, 1):
    aid = ap["apparel_id"]
    pnum = ap.get("product_number", "")
    snk_num = num_int(ap.get("number") or pnum)
    print(f"[{i}/{len(apparels)}] {aid} {pnum} {ap.get('rarity','')} ...", end="", flush=True)

    png = fetch_png(aid, ap.get("image_url", ""))
    img_rel_scanner = f"{IMG_REL_FOR_SCANNER}/{aid}.png" if png else None

    top1_id = top1_name = top1_rar = top1_ref = ""
    top1_score = None
    top5 = []
    scan_err = "no_image"
    if png:
        data, scan_err = scan(img_rel_scanner)
        if data:
            tr = data["topResult"]
            top1_id, top1_name = tr["cardId"], tr["name"]
            top1_rar, top1_ref = tr.get("rarityCode", ""), tr.get("scrydexRef", "")
            top1_score = round(float(tr["score"]), 4)
            for c in data.get("candidates", [])[:5]:
                top5.append({"cardId": c["cardId"], "name": c["name"],
                             "rarity": c.get("rarityCode", ""), "ref": c.get("scrydexRef", ""),
                             "score": round(float(c["score"]), 4)})
    print(f" scan={top1_score} {top1_name}")

    # 텍스트 매칭
    tm = catalog_by_num.get(snk_num)
    text_id = tm["card_id"] if tm else ""

    # 교차검증
    has_text = bool(text_id)
    has_scan = bool(top1_id) and top1_score is not None
    scan_confident = has_scan and top1_score >= SCAN_CONFIDENT
    if has_text and has_scan and top1_id == text_id:
        status, conf = "HIGH_CONFIDENCE", "HIGH"
    elif has_text and scan_confident and top1_id != text_id:
        status, conf = "CONFLICT", "REVIEW"
    elif has_text and (not scan_confident):
        status, conf = "TEXT_MATCH_ONLY", "MED"
    elif (not has_text) and scan_confident:
        status, conf = "IMAGE_MATCH_ONLY", "MED"
    elif has_text and has_scan and top1_id == text_id:
        status, conf = "HIGH_CONFIDENCE", "HIGH"
    else:
        status, conf = "NOT_FOUND", "LOW"

    our = tm or {}
    rows.append({
        "our_card_id": our.get("card_id", ""),
        "our_name": our.get("name", ""),
        "our_jp_ref": our.get("jp_ref", ""),
        "our_set_code": "M3",
        "our_card_no": our.get("num", ap.get("number", "")),
        "our_rarity": our.get("rarity", ""),
        "our_image_path": our.get("img_jp", "") if our else "",
        "snkrdunk_id": aid,
        "snkrdunk_url": ap.get("detail_url", f"https://snkrdunk.com/apparels/{aid}"),
        "snkrdunk_title": ap.get("jp_title", ""),
        "snkrdunk_product_number": pnum,
        "snkrdunk_image_url": ap.get("image_url", ""),
        "snkrdunk_image_cache_path": img_rel_scanner or "",
        "text_match_card_id": text_id,
        "scanner_top1_card_id": top1_id,
        "scanner_top1_name": top1_name,
        "scanner_top1_score": top1_score if top1_score is not None else "",
        "scanner_top5_json": json.dumps(top5, ensure_ascii=False),
        "match_status": status,
        "confidence": conf,
        "notes": scan_err or "",
        # 표시용 부가 (CSV엔 안 들어가는 sold)
        "_sold": sales.get(aid),
        "_snk_rarity": ap.get("rarity", ""),
        "_top5": top5,
    })

# ---- 6a. CSV ----
CSV_COLS = ["our_card_id","our_name","our_jp_ref","our_set_code","our_card_no","our_rarity",
            "our_image_path","snkrdunk_id","snkrdunk_url","snkrdunk_title","snkrdunk_product_number",
            "snkrdunk_image_url","snkrdunk_image_cache_path","text_match_card_id","scanner_top1_card_id",
            "scanner_top1_name","scanner_top1_score","scanner_top5_json","match_status","confidence","notes"]
with open(CSV_OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=CSV_COLS, extrasaction="ignore")
    w.writeheader()
    for r in rows:
        w.writerow(r)
print(f"\n[CSV] {CSV_OUT}")

# 통계
from collections import Counter
stat = Counter(r["match_status"] for r in rows)
print("[통계]", dict(stat))

# ---- 6b. HTML ----
def esc(s): return html.escape(str(s if s is not None else ""))

STATUS_COLOR = {"HIGH_CONFIDENCE":"#1a7f37","CONFLICT":"#cf222e","TEXT_MATCH_ONLY":"#9a6700",
                "IMAGE_MATCH_ONLY":"#0969da","NOT_FOUND":"#6e7781"}

cards_html = []
for r in sorted(rows, key=lambda x: (x["match_status"]!="CONFLICT", x["our_card_no"])):
    aid = r["snkrdunk_id"]
    our_img = f"scanner/data/{r['our_image_path']}" if r["our_image_path"] else ""
    snk_img = f"scanner/data/{r['snkrdunk_image_cache_path']}" if r["snkrdunk_image_cache_path"] else ""
    sc = STATUS_COLOR.get(r["match_status"], "#333")
    sold = r["_sold"]
    sold_html = ""
    if sold:
        sold_html = (f"<div class='sold'>💴 sold {sold['count']}건 · median <b>¥{sold['median']:,}</b> "
                     f"(¥{sold['min']:,}~¥{sold['max']:,}) · 최근 {esc(sold['latest'])}</div>")
    # top5
    t5 = []
    for j, c in enumerate(r["_top5"]):
        hit = "★" if c["cardId"] == r["text_match_card_id"] else ""
        cimg = f"scanner/data/cards/{c['cardId']}_jp.png"
        t5.append(
            f"<div class='t5{ ' t5hit' if hit else ''}'>"
            f"<img loading='lazy' src='{esc(cimg)}' onerror=\"this.style.opacity=.15\">"
            f"<div class='t5m'><b>{j+1}.{hit}</b> {esc(c['name'])} <span class='rar'>{esc(c['rarity'])}</span><br>"
            f"<span class='ref'>{esc(c['ref'])}</span> · <span class='sc'>{c['score']}</span></div></div>")
    t5_html = "".join(t5) or "<i>스캐너 결과 없음</i>"

    cards_html.append(f"""
<div class="card" data-id="{esc(aid)}" data-status="{esc(r['match_status'])}">
  <div class="hd">
    <span class="badge" style="background:{sc}">{esc(r['match_status'])}</span>
    <span class="cno">M3 {esc(r['our_card_no'])}</span>
    <span class="conf">conf {esc(r['confidence'])}</span>
  </div>
  <div class="body">
    <div class="col our">
      <div class="lbl">우리 카드</div>
      <img class="big" loading="lazy" src="{esc(our_img)}" onerror="this.style.opacity=.12">
      <div class="meta"><b>{esc(r['our_name'])}</b><br>
        <span class="mono">{esc(r['our_card_id'])}</span><br>
        {esc(r['our_jp_ref'])} · {esc(r['our_rarity'])}</div>
    </div>
    <div class="col snk">
      <div class="lbl">SNKRDUNK</div>
      <img class="big" loading="lazy" src="{esc(snk_img)}" onerror="this.style.opacity=.12">
      <div class="meta"><b>{esc(r['snkrdunk_title'])}</b><br>
        <span class="mono">{esc(r['snkrdunk_product_number'])}</span> · {esc(r['_snk_rarity'])}<br>
        <a href="{esc(r['snkrdunk_url'])}" target="_blank">▶ {esc(r['snkrdunk_url'])}</a></div>
      {sold_html}
    </div>
    <div class="col match">
      <div class="lbl">교차검증</div>
      <div class="mrow">텍스트(M3+번호) → <b>{esc(r['scanner_top1_name'] if False else r['our_name'] or '—')}</b>
        <span class="mono small">{esc(r['text_match_card_id'] or '—')}</span></div>
      <div class="mrow">스캐너 top1 → <b>{esc(r['scanner_top1_name'] or '—')}</b>
        <span class="sc">{esc(r['scanner_top1_score'])}</span>
        <span class="mono small">{esc(r['scanner_top1_card_id'] or '—')}</span></div>
      <div class="t5wrap">{t5_html}</div>
      <div class="judge">
        <button data-j="match">✓ 매칭</button>
        <button data-j="no">✗ 아님</button>
        <button data-j="hold">? 보류</button>
        <span class="jstate"></span>
      </div>
    </div>
  </div>
</div>""")

JS = """
const J=JSON.parse(localStorage.getItem('snk_m3_judge')||'{}');
function paint(el){const id=el.dataset.id;const v=J[id];const s=el.querySelector('.jstate');
  el.querySelectorAll('.judge button').forEach(b=>b.classList.toggle('on',b.dataset.j===v));
  s.textContent=v?('판정: '+({match:'✓ 매칭',no:'✗ 아님',hold:'? 보류'}[v])):'';}
document.querySelectorAll('.card').forEach(el=>{paint(el);
  el.querySelectorAll('.judge button').forEach(b=>{b.onclick=()=>{
    J[el.dataset.id]=b.dataset.j;localStorage.setItem('snk_m3_judge',JSON.stringify(J));paint(el);upd();};});});
function upd(){const n=Object.keys(J).length;document.getElementById('jcount').textContent=n;}
function flt(){const s=document.getElementById('fstatus').value;const u=document.getElementById('funjudged').checked;
  document.querySelectorAll('.card').forEach(el=>{let ok=true;
    if(s&&el.dataset.status!==s)ok=false;
    if(u&&J[el.dataset.id])ok=false;
    el.style.display=ok?'':'none';});}
function expt(){let out='snkrdunk_id,verdict\\n';for(const k in J)out+=k+','+J[k]+'\\n';
  const b=new Blob([out],{type:'text/csv'});const a=document.createElement('a');
  a.href=URL.createObjectURL(b);a.download='snkrdunk_m3_verdicts.csv';a.click();}
document.getElementById('fstatus').onchange=flt;document.getElementById('funjudged').onchange=flt;
document.getElementById('expt').onclick=expt;upd();
"""

statline = " · ".join(f"{k}: {v}" for k, v in stat.items())
page = f"""<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>SNKRDUNK M3 스캐너 교차검증 검수</title>
<style>
*{{box-sizing:border-box}} body{{font-family:-apple-system,'Apple SD Gothic Neo',sans-serif;margin:0;background:#f6f8fa;color:#1f2328}}
.top{{position:sticky;top:0;background:#24292f;color:#fff;padding:12px 16px;z-index:10;display:flex;gap:14px;align-items:center;flex-wrap:wrap}}
.top b{{font-size:16px}} .top .stat{{font-size:12px;opacity:.85}}
.top select,.top label{{font-size:13px}} .top button{{padding:5px 12px;border:0;border-radius:6px;background:#2da44e;color:#fff;cursor:pointer}}
.wrap{{max-width:1100px;margin:0 auto;padding:14px}}
.card{{background:#fff;border:1px solid #d0d7de;border-radius:10px;margin:12px 0;overflow:hidden}}
.hd{{display:flex;gap:10px;align-items:center;padding:8px 12px;border-bottom:1px solid #eaeef2;background:#fafbfc}}
.badge{{color:#fff;font-size:11px;font-weight:700;padding:3px 8px;border-radius:20px}}
.cno{{font-weight:700}} .conf{{font-size:12px;color:#57606a;margin-left:auto}}
.body{{display:grid;grid-template-columns:1fr 1fr 1.3fr;gap:10px;padding:12px}}
@media(max-width:820px){{.body{{grid-template-columns:1fr}}}}
.col{{min-width:0}} .lbl{{font-size:11px;font-weight:700;color:#57606a;text-transform:uppercase;margin-bottom:6px}}
.big{{width:100%;max-width:230px;border-radius:8px;background:#f0f0f0;display:block}}
.meta{{font-size:13px;margin-top:6px;line-height:1.5}} .mono{{font-family:ui-monospace,monospace;font-size:11px;color:#57606a}}
.small{{font-size:10px}} a{{color:#0969da;word-break:break-all;font-size:12px}}
.sold{{margin-top:6px;font-size:12px;background:#fff8e5;border:1px solid #f0d58c;padding:5px 8px;border-radius:6px}}
.mrow{{font-size:13px;margin:3px 0}} .sc{{color:#1a7f37;font-weight:700}} .rar{{color:#8250df;font-size:11px}}
.ref{{font-family:ui-monospace,monospace;font-size:10px;color:#57606a}}
.t5wrap{{display:flex;gap:6px;flex-wrap:wrap;margin:8px 0;padding:8px;background:#f6f8fa;border-radius:8px}}
.t5{{width:74px;font-size:10px;text-align:center}} .t5 img{{width:70px;height:96px;object-fit:cover;border-radius:4px;border:2px solid transparent}}
.t5hit img{{border-color:#1a7f37}} .t5m{{line-height:1.3;margin-top:2px}}
.judge{{margin-top:10px;display:flex;gap:8px;align-items:center}}
.judge button{{padding:7px 14px;border:1px solid #d0d7de;border-radius:7px;background:#fff;cursor:pointer;font-size:14px}}
.judge button.on{{background:#0969da;color:#fff;border-color:#0969da}} .jstate{{font-size:12px;color:#57606a}}
</style></head><body>
<div class="top">
  <b>SNKRDUNK M3 ↔ 우리카드 교차검증</b>
  <span class="stat">{esc(statline)} · 총 {len(rows)}</span>
  <label>상태 <select id="fstatus"><option value="">전체</option>
    <option>HIGH_CONFIDENCE</option><option>CONFLICT</option><option>TEXT_MATCH_ONLY</option>
    <option>IMAGE_MATCH_ONLY</option><option>NOT_FOUND</option></select></label>
  <label><input type="checkbox" id="funjudged"> 미판정만</label>
  <span class="stat">판정 <b id="jcount">0</b></span>
  <button id="expt">CSV 내보내기</button>
</div>
<div class="wrap">
{''.join(cards_html)}
</div>
<script>{JS}</script>
</body></html>"""

with open(HTML_OUT, "w", encoding="utf-8") as f:
    f.write(page)
print(f"[HTML] {HTML_OUT}")
