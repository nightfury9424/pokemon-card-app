#!/usr/bin/env python3
"""우리 카탈로그(3755) ↔ SNKRDUNK 검수 HTML 생성.
- 우리 카드 이미지(scanner/data/cards/{card_id}_jp.png) + 메타(set/번호/레어도)
- SNKRDUNK 링크: 수집된 카드(M3 pilot)=직접 apparel 링크 + SNKRDUNK 이미지 + JP sold median
                 미수집=번호 기반 SNKRDUNK 검색링크(site:snkrdunk.com product_number)
- 검수 UI: 카드별 ✓매칭/✗아님/?보류 → localStorage 저장 → CSV export
출력: snkrdunk_review_all.html (repo 루트, 이미지 상대경로). 로컬 전용·prod write 0.
"""
import csv, re, os, html, collections, statistics, json

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CAT = os.path.join(REPO, "python/catalog_gapfill/prod_cards_full_20260620.csv")
SNK = os.path.expanduser("~/Downloads/price_v8_snkrdunk")
OUT = os.path.join(REPO, "snkrdunk_review_all.html")
IMG = "scanner/data/cards"  # repo 루트 기준 상대경로

def num_of(s):
    s = str(s).split("/")[0]; d = re.sub(r"\D", "", s); return int(d) if d else None

# ── SNKRDUNK 수집 데이터: (set,num) -> {apparel_id,image,sold_median,sold_n} ──
snk_idx = {}
cat_path = os.path.join(SNK, "snkrdunk_apparel_catalog.csv")
if os.path.exists(cat_path):
    for r in csv.DictReader(open(cat_path)):
        m = re.match(r"pkmn-tcg-(\w+)-(\d+)", r.get("product_number") or "")
        if m:
            snk_idx[(m.group(1).lower(), int(m.group(2)))] = {
                "aid": r["apparel_id"], "img": r.get("image_url", ""),
                "title": r.get("jp_title", "")}
ck = os.path.join(SNK, "apparel_scan_checkpoint.csv")
if os.path.exists(ck):
    for r in csv.DictReader(open(ck)):
        if r.get("status") == "POKEMON" and r.get("set") and num_of(r.get("number")):
            key = (r["set"].lower(), num_of(r["number"]))
            snk_idx.setdefault(key, {"aid": r["apparel_id"], "img": "", "title": r.get("product_number", "")})
sales = collections.defaultdict(list)
sp = os.path.join(SNK, "snkrdunk_recent_sales_by_apparel.csv")
if os.path.exists(sp):
    for r in csv.DictReader(open(sp)):
        if (r.get("price_jpy") or "").isdigit():
            sales[r["apparel_id"]].append(int(r["price_jpy"]))

# ── 카탈로그 ──
def img_rel(cid):
    for s in ("_jp.png", "_en.png", "_ko.png"):
        if os.path.exists(os.path.join(REPO, IMG, cid + s)):
            return f"{IMG}/{cid}{s}"
    return None

cards = []
for r in csv.DictReader(open(CAT)):
    m = re.match(r"([a-z0-9]+)_ja-(\d+)", r.get("jp_scrydex_ref") or "")
    setc, num = (m.group(1), int(m.group(2))) if m else ("", None)
    cards.append({**r, "set": setc, "num": num, "img": img_rel(r["card_id"])})

# set 정렬: mega(m*) → sv* → swsh* → sm* → xy* → 기타, 그 안에서 set 내림차순·번호
def set_rank(s):
    if s.startswith("m") and not s.startswith("sm"): return (0, s)
    if s.startswith("sv"): return (1, s)
    if s.startswith("swsh"): return (2, s)
    if s.startswith("sm"): return (3, s)
    if s.startswith("xy"): return (4, s)
    return (5, s)
by_set = collections.defaultdict(list)
for c in cards: by_set[c["set"]].append(c)
sets_sorted = sorted(by_set.keys(), key=lambda s: (set_rank(s)[0], s), reverse=False)

matched_total = sum(1 for c in cards if (c["set"], c["num"]) in snk_idx)

def esc(x): return html.escape(str(x or ""))

rows_html = []
for setc in sets_sorted:
    group = sorted(by_set[setc], key=lambda c: (c["num"] or 9999))
    mcount = sum(1 for c in group if (c["set"], c["num"]) in snk_idx)
    open_attr = " open" if mcount else ""
    rows_html.append(f'<details{open_attr} data-set="{esc(setc or "NO")}"><summary>{esc(setc or "(세트없음)")} · {len(group)}장 · 수집매칭 {mcount}</summary><div class="grid">')
    for c in group:
        cid = c["card_id"]; key = (c["set"], c["num"])
        pn = f"pkmn-tcg-{c['set'].upper()}-{c['num']:03d}" if c["set"] and c["num"] else ""
        snk = snk_idx.get(key)
        img = f'<img loading="lazy" src="{esc(c["img"])}">' if c["img"] else '<div class="noimg">no img</div>'
        rar = esc(c["rarity_code"])
        if snk:
            aid = snk["aid"]
            link = f'<a href="https://snkrdunk.com/apparels/{esc(aid)}" target="_blank">▶ SNKRDUNK #{esc(aid)}</a>'
            ps = sales.get(aid, [])
            sold = (f'<span class="sold">JP sold {len(ps)}건 median ¥{int(statistics.median(ps)):,} '
                    f'≈{int(statistics.median(ps)*9.1):,}원</span>') if ps else '<span class="nosold">sold 미수집</span>'
            snkimg = f'<img loading="lazy" class="snk" src="{esc(snk["img"])}">' if snk.get("img") else ''
            badge = '<span class="b ok">수집됨</span>'
        else:
            q = pn or f"{c['set']} {c['num']}"
            link = f'<a href="https://www.google.com/search?q=site:snkrdunk.com+{esc(q)}" target="_blank">🔍 SNKRDUNK 검색</a>'
            sold = snkimg = ''
            badge = '<span class="b no">미수집</span>'
        rows_html.append(
            f'<div class="card" data-cid="{esc(cid)}" data-rar="{rar}" data-m="{1 if snk else 0}">'
            f'<div class="imgs">{img}{snkimg}</div>'
            f'<div class="meta"><b>{esc(c["name"])}</b> <span class="rar">{rar}</span>{badge}<br>'
            f'<span class="dim">{esc(c["set"])} · {esc(c["collection_number"])} · {esc(pn)}</span><br>'
            f'{link} {sold}</div>'
            f'<div class="judge"><button data-j="ok">✓</button><button data-j="no">✗</button><button data-j="hold">?</button></div>'
            f'</div>')
    rows_html.append('</div></details>')

set_opts = "".join(f'<option value="{esc(s or "NO")}">{esc(s or "(없음)")}</option>' for s in sets_sorted)
HTML = f"""<!doctype html><html lang=ko><head><meta charset=utf-8>
<title>SNKRDUNK 검수 — {len(cards)}장</title>
<style>
body{{background:#0b0f14;color:#dfe7f0;font:14px/1.5 -apple-system,system-ui,sans-serif;margin:0;padding:12px}}
.bar{{position:sticky;top:0;background:#0b0f14;padding:8px 0;border-bottom:1px solid #223;z-index:9;display:flex;gap:8px;flex-wrap:wrap;align-items:center}}
.bar b{{color:#7fd1ff}} select,button{{background:#16202c;color:#dfe7f0;border:1px solid #2a3a4a;border-radius:6px;padding:5px 9px;font-size:13px}}
details{{margin:8px 0;border:1px solid #1c2733;border-radius:8px}} summary{{padding:8px 12px;cursor:pointer;font-weight:700;color:#9fb}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:8px;padding:10px}}
.card{{display:flex;gap:8px;background:#101820;border:1px solid #1c2733;border-radius:8px;padding:8px}}
.card.j-ok{{outline:2px solid #2ecc71}} .card.j-no{{outline:2px solid #e74c3c;opacity:.5}} .card.j-hold{{outline:2px solid #f1c40f}}
.imgs{{display:flex;gap:4px}} .imgs img{{width:62px;height:86px;object-fit:cover;border-radius:5px;background:#222}}
.imgs img.snk{{outline:1px solid #7fd1ff}} .noimg{{width:62px;height:86px;display:flex;align-items:center;justify-content:center;color:#456;font-size:10px;background:#16202c}}
.meta{{flex:1;min-width:0}} .rar{{color:#f1c40f;font-size:11px;font-weight:700;margin-left:4px}} .dim{{color:#6b8198;font-size:11px}}
.b{{font-size:10px;padding:1px 5px;border-radius:4px;margin-left:6px}} .b.ok{{background:#16402a;color:#5fe6a0}} .b.no{{background:#2a2230;color:#8a7}}
.sold{{color:#5fe6a0;font-size:11px}} .nosold{{color:#667;font-size:11px}} a{{color:#7fd1ff}}
.judge{{display:flex;flex-direction:column;gap:3px}} .judge button{{padding:3px 7px}}
</style></head><body>
<div class=bar>
<b>SNKRDUNK 검수</b> 총 {len(cards)}장 · 수집매칭 {matched_total}장
세트<select id=fset><option value="">전체</option>{set_opts}</select>
레어도<select id=frar><option value="">전체</option><option>MUR</option><option>UR</option><option>SAR</option><option>SR</option><option>HR</option><option>CHR</option><option>CSR</option><option>AR</option><option>RR</option><option>RRR</option></select>
<label><input type=checkbox id=fmatch> 수집매칭만</label>
<label><input type=checkbox id=fundone> 미판정만</label>
<button id=exp>✓ 판정 CSV 내보내기</button> <span id=cnt></span>
</div>
{''.join(rows_html)}
<script>
const J=JSON.parse(localStorage.getItem('snk_judge')||'{{}}');
function paint(el){{const c=el.dataset.cid;el.classList.remove('j-ok','j-no','j-hold');if(J[c])el.classList.add('j-'+J[c]);}}
document.querySelectorAll('.card').forEach(el=>{{paint(el);el.querySelectorAll('.judge button').forEach(b=>b.onclick=()=>{{J[el.dataset.cid]=b.dataset.j;localStorage.setItem('snk_judge',JSON.stringify(J));paint(el);cnt();}});}});
function applyF(){{const s=fset.value,r=frar.value,m=fmatch.checked,u=fundone.checked;
 document.querySelectorAll('details').forEach(d=>{{let any=false;d.querySelectorAll('.card').forEach(c=>{{
  let ok=(!r||c.dataset.rar===r)&&(!m||c.dataset.m==='1')&&(!u||!J[c.dataset.cid]);c.style.display=ok?'':'none';if(ok)any=true;}});
  d.style.display=(!s||d.dataset.set===s)&&any?'':'none';}});}}
[fset,frar,fmatch,fundone].forEach(e=>e.onchange=applyF);
function cnt(){{const v=Object.values(J);document.getElementById('cnt').textContent=`판정 ${{v.length}} (✓${{v.filter(x=>x=='ok').length}} ✗${{v.filter(x=>x=='no').length}} ?${{v.filter(x=>x=='hold').length}})`;}}
exp.onclick=()=>{{let csv='card_id,judgment\\n';for(const k in J)csv+=k+','+J[k]+'\\n';
 const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{{type:'text/csv'}}));a.download='snkrdunk_judge.csv';a.click();}};
cnt();
</script></body></html>"""
open(OUT, "w").write(HTML)
print(f"생성: {OUT}")
print(f"  카드 {len(cards)}장 / 세트 {len(sets_sorted)}개 / 수집매칭 {matched_total}장")
print(f"  이미지 보유 {sum(1 for c in cards if c['img'])}/{len(cards)}")
