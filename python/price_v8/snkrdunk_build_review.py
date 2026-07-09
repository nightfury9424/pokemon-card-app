#!/usr/bin/env python3
"""SNK 풀스캔 결과(snk_scan_results.jsonl) → 우리 등록카드 후보 버킷팅 → CSV 2종 + 검수 HTML.

스캐너가 먼저 판별: SNK 이미지의 top1/top5 가 우리 등록 3,755장에 들어오면 후보, 아니면 OUT_OF_SCOPE.
set/number/rarity 는 선필터 아님 — 여기서 '검증/분류'용으로만 사용.
검수 HTML = 우리 등록 카드 후보만(OUT_OF_SCOPE 제외). 사람이 HIGH/MED/MANUAL/MISMATCH 판정.

부분 jsonl 로도 돌아감(스캔 진행 중 미리보기 가능).
"""
import csv, json, os, re, html
from collections import defaultdict

ROOT = "/Users/fury/pokemon-card-app"
BIG = os.path.expanduser("~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv")
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
RESULTS = f"{ROOT}/python/price_v8/snk_scan_results.jsonl"
FULL_CSV = f"{ROOT}/python/price_v8/snkrdunk_full_image_scan_results.csv"
CAND_CSV = f"{ROOT}/python/price_v8/snkrdunk_registered_image_candidates.csv"
HTML_OUT = f"{ROOT}/snkrdunk_scanner_candidate_review.html"
HIGH_SCORE = 0.80

def num_int(s):
    m = re.search(r"(\d+)", str(s or "").split("/")[0].split("-")[-1])
    return int(m.group(1)) if m else None

# 우리 등록카드
reg = {}
with open(CATALOG, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        m = re.match(r"^([a-z0-9]+)_ja-(\d+)", (r.get("jp_scrydex_ref") or ""))
        reg[r["card_id"]] = {
            "name": r["name"], "jp_ref": (r.get("jp_scrydex_ref") or ""), "rarity": r["rarity_code"],
            "set": (m.group(1).upper() if m else ""), "num": (int(m.group(2)) if m else None),
            "coll": r["collection_number"],
            "img": next((f"cards/{r['card_id']}{s}.png" for s in ("_jp","_ko","_en")
                         if os.path.exists(f"{ROOT}/scanner/data/cards/{r['card_id']}{s}.png")), ""),
        }
print(f"[등록카드] {len(reg)}")

# SNK 41,610 메타 (apparel_id → 정보)
snk = {}
with open(BIG, encoding="utf-8") as f:
    for r in csv.DictReader(f):
        snk[str(r["apparel_id"])] = {
            "pn": r.get("product_number",""), "title": r.get("jp_title",""),
            "set": (r.get("set") or "").upper(), "number": r.get("number",""),
            "num_int": num_int(r.get("number")), "rarity": r.get("rarity",""),
            "image_url": r.get("image_url",""),
            "detail_url": r.get("detail_url", f"https://snkrdunk.com/apparels/{r['apparel_id']}"),
        }
print(f"[SNK catalog] {len(snk)}")

# 스캔 결과 읽기 → 버킷
def bucket(rec):
    if rec.get("note") == "IMAGE_FETCH_FAILED": return "IMAGE_FETCH_FAILED", None, None
    t1 = rec.get("top1") or {}
    if not t1 or t1.get("id") is None:
        if not rec.get("top5"): return "SCANNER_ERR" if rec.get("note") not in ("not_found","ok","low_confidence") else "OUT_OF_SCOPE", None, None
    if t1.get("id") in reg:
        return "REGISTERED_TOP1", t1["id"], 1
    for i, c in enumerate(rec.get("top5") or [], 1):
        if c["cardId"] in reg:
            return "REGISTERED_TOP5", c["cardId"], i
    return "OUT_OF_SCOPE", None, None

full_rows = []           # 전체 스캔 로그
cand = []                # 등록 후보 (apparel→our card)
seen = set()
with open(RESULTS, encoding="utf-8") as f:
    for line in f:
        try: rec = json.loads(line)
        except Exception: continue
        aid = rec["aid"]
        if aid in seen: continue
        seen.add(aid)
        b, cid, rank = bucket(rec)
        meta = snk.get(aid, {})
        t1 = rec.get("top1") or {}
        full_rows.append({
            "apparel_id": aid, "product_number": meta.get("pn",""), "snkrdunk_title": meta.get("title",""),
            "set": meta.get("set",""), "number": meta.get("number",""), "rarity": meta.get("rarity",""),
            "image_url": meta.get("image_url",""), "image_cache_path": rec.get("img") or "",
            "scanner_status": rec.get("note",""),
            "scanner_top1_card_id": t1.get("id",""), "scanner_top1_name": t1.get("name",""),
            "scanner_top1_score": t1.get("score",""),
            "scanner_top5_json": json.dumps(rec.get("top5") or [], ensure_ascii=False),
            "top1_is_registered": "Y" if (t1.get("id") in reg) else "",
            "match_bucket": b,
        })
        if b in ("REGISTERED_TOP1","REGISTERED_TOP5"):
            o = reg[cid]; score = (t1.get("score") if rank==1 else (rec["top5"][rank-1]["score"]))
            # 검증: SNK 번호 vs 우리 카드 번호
            snum = meta.get("num_int"); set_num_ok = (snum is not None and snum == o["num"])
            rar_ok = (meta.get("rarity","").upper() == (o["rarity"] or "").upper())
            if rank == 1 and score is not None and score >= HIGH_SCORE and set_num_ok:
                st = "HIGH_CONFIDENCE"
            elif rank == 1:
                st = "IMAGE_MATCH_NEEDS_REVIEW"
            else:
                st = "TOP5_NEEDS_REVIEW"
            cand.append({
                "our_card_id": cid, "our_name": o["name"], "our_jp_ref": o["jp_ref"], "our_rarity": o["rarity"],
                "our_img": o["img"], "our_coll": o["coll"], "our_set": o["set"], "our_num": o["num"],
                "snkrdunk_apparel_id": aid, "snkrdunk_product_number": meta.get("pn",""),
                "snkrdunk_title": meta.get("title",""), "snkrdunk_image_url": meta.get("image_url",""),
                "snkrdunk_image_cache_path": rec.get("img") or "", "snkrdunk_detail_url": meta.get("detail_url",""),
                "scanner_rank": rank, "scanner_score": score,
                "scanner_top5_json": json.dumps(rec.get("top5") or [], ensure_ascii=False),
                "set_number_check": "OK" if set_num_ok else "DIFF", "rarity_check": "OK" if rar_ok else "DIFF",
                "match_status": st, "notes": "",
            })

from collections import Counter
bc = Counter(r["match_bucket"] for r in full_rows)
print(f"[버킷] {dict(bc)}")
print(f"[후보] 등록카드 후보 {len(cand)} · 고유 our_card {len({c['our_card_id'] for c in cand})}")

# CSV 1: 전체
with open(FULL_CSV, "w", newline="", encoding="utf-8") as f:
    cols=["apparel_id","product_number","snkrdunk_title","set","number","rarity","image_url","image_cache_path",
          "scanner_status","scanner_top1_card_id","scanner_top1_name","scanner_top1_score","scanner_top5_json",
          "top1_is_registered","match_bucket"]
    w=csv.DictWriter(f,fieldnames=cols,extrasaction="ignore"); w.writeheader()
    for r in full_rows: w.writerow(r)
# CSV 2: 후보만
with open(CAND_CSV, "w", newline="", encoding="utf-8") as f:
    cols=["our_card_id","our_name","our_jp_ref","our_rarity","snkrdunk_apparel_id","snkrdunk_product_number",
          "snkrdunk_title","snkrdunk_image_url","snkrdunk_image_cache_path","scanner_rank","scanner_score",
          "scanner_top5_json","set_number_check","rarity_check","match_status","notes"]
    w=csv.DictWriter(f,fieldnames=cols,extrasaction="ignore"); w.writeheader()
    for r in cand: w.writerow(r)
print(f"[CSV] {FULL_CSV}\n[CSV] {CAND_CSV}")

# ── 커버리지 통계 (row 아님, 고유 우리 card_id 기준) ──
from collections import defaultdict as _dd
cbc = _dd(list)
for c in cand: cbc[c["our_card_id"]].append(c)
_BEST = {"HIGH_CONFIDENCE":0,"IMAGE_MATCH_NEEDS_REVIEW":1,"TOP5_NEEDS_REVIEW":2,"CONFLICT":0}
card_status = {cid: min(cs, key=lambda x:_BEST.get(x["match_status"],9))["match_status"] for cid, cs in cbc.items()}
uniq = len(cbc)
n1 = sum(1 for cs in cbc.values() if len(cs) == 1)
n2 = sum(1 for cs in cbc.values() if len(cs) >= 2)
reg_total = len(reg)
no_jp = sum(1 for o in reg.values() if not o["set"])
no_cand = reg_total - uniq
cs_cnt = Counter(card_status.values())
print("="*50)
print(f"[커버리지·고유 card 기준]")
print(f"  SNK catalog row            : {len(snk)}")
print(f"  스캔 완료 row              : {len(full_rows)}")
print(f"  IMAGE_FETCH_FAILED         : {bc.get('IMAGE_FETCH_FAILED',0)}")
print(f"  SCANNER_ERR                : {bc.get('SCANNER_ERR',0)}")
print(f"  REGISTERED_TOP1 row        : {bc.get('REGISTERED_TOP1',0)}")
print(f"  REGISTERED_TOP5 row        : {bc.get('REGISTERED_TOP5',0)}")
print(f"  OUT_OF_SCOPE row           : {bc.get('OUT_OF_SCOPE',0)}")
print(f"  ── 우리 카드 {reg_total}장 중 ──")
print(f"  후보 잡힌 고유 card        : {uniq}")
print(f"  후보 0개 card              : {no_cand}  (그중 NO_JP_REF {no_jp})")
print(f"  후보 1개 card              : {n1}")
print(f"  후보 2개+ card             : {n2}")
print(f"  [card-best] HIGH_CONFIDENCE: {cs_cnt.get('HIGH_CONFIDENCE',0)}")
print(f"  [card-best] IMAGE_NEEDS_REVIEW: {cs_cnt.get('IMAGE_MATCH_NEEDS_REVIEW',0)}")
print(f"  [card-best] TOP5_NEEDS_REVIEW : {cs_cnt.get('TOP5_NEEDS_REVIEW',0)}")
print(f"  [card-best] CONFLICT       : {cs_cnt.get('CONFLICT',0)}")
print("="*50)

# ── HTML: 우리 등록카드 기준, 후보 그룹핑 ──
def esc(s): return html.escape(str(s if s is not None else ""))
by_card = defaultdict(list)
for c in cand: by_card[c["our_card_id"]].append(c)
for cid in by_card: by_card[cid].sort(key=lambda x:(x["scanner_rank"], -(x["scanner_score"] or 0)))
STP={"HIGH_CONFIDENCE":"#1a7f37","IMAGE_MATCH_NEEDS_REVIEW":"#9a6700","TOP5_NEEDS_REVIEW":"#bc4c00","CONFLICT":"#cf222e"}
ORD={"HIGH_CONFIDENCE":0,"IMAGE_MATCH_NEEDS_REVIEW":1,"TOP5_NEEDS_REVIEW":2,"CONFLICT":0}
cards_sorted=sorted(by_card.items(), key=lambda kv:(ORD.get(kv[1][0]["match_status"],9), reg[kv[0]]["set"] or "", reg[kv[0]]["num"] or 0))

def cand_block(c, primary):
    snk_img=f"scanner/data/{c['snkrdunk_image_cache_path']}" if c['snkrdunk_image_cache_path'] else ""
    cls="snkbig" if primary else "snksm"
    return (f"<div class='{cls}'><img loading='lazy' src='{esc(snk_img)}' onerror=\"this.style.opacity=.12\">"
            f"<div class='cm'><span class='mono'>{esc(c['snkrdunk_product_number'])}</span> · rank{c['scanner_rank']} · "
            f"<b class='sc'>{esc(c['scanner_score'])}</b><br>set:{esc(c['set_number_check'])} rar:{esc(c['rarity_check'])} · "
            f"<a href='{esc(c['snkrdunk_detail_url'])}' target='_blank'>apparel {esc(c['snkrdunk_apparel_id'])}</a></div></div>")

blocks=[]
for cid, cs in cards_sorted:
    o=reg[cid]; top=cs[0]; sc=STP.get(top["match_status"],"#333")
    our_img=f"scanner/data/{o['img']}" if o["img"] else ""
    t5=[]
    for j,x in enumerate(json.loads(top["scanner_top5_json"])):
        hit="★" if x["cardId"]==cid else ""
        t5.append(f"<div class='t5{' h' if hit else ''}'><img loading='lazy' src='scanner/data/cards/{esc(x['cardId'])}_jp.png' onerror=\"this.style.opacity=.12\"><div>{j+1}.{hit}{esc(x['name'])[:8]}<br>{esc(x['score'])}</div></div>")
    others="".join(cand_block(c,False) for c in cs[1:6])
    blocks.append(f"""<div class="card" data-id="{esc(cid)}" data-status="{esc(top['match_status'])}">
  <div class="hd"><span class="badge" style="background:{sc}">{esc(top['match_status'])}</span>
    <span class="nm">{esc(o['name'])} · {esc(o['set'])} {esc(o['coll'])} · {esc(o['rarity'])}</span>
    <span class="cnt">SNK후보 {len(cs)}</span><span class="cid">{esc(cid)}</span></div>
  <div class="body">
    <div class="col"><div class="lbl">우리 카드</div><img class="big" loading="lazy" src="{esc(our_img)}" onerror="this.style.opacity=.12">
      <div class="cm"><b>{esc(o['name'])}</b><br><span class="mono">{esc(o['jp_ref'])}</span> · {esc(o['rarity'])}</div></div>
    <div class="col"><div class="lbl">SNK 후보(스캐너 1위)</div>{cand_block(top,True)}
      <div class="others">{others}</div></div>
    <div class="col"><div class="lbl">스캐너 top5</div><div class="t5wrap">{''.join(t5)}</div>
      <div class="judge"><button data-j="HIGH">HIGH</button><button data-j="MED">MED</button>
        <button data-j="MANUAL">MANUAL</button><button data-j="MISMATCH">MISMATCH</button><span class="js"></span></div></div>
  </div></div>""")

bstat=" · ".join(f"{k}:{v}" for k,v in bc.items())
JS="""const J=JSON.parse(localStorage.getItem('snk_scanrev')||'{}');
function pa(e){const v=J[e.dataset.id],s=e.querySelector('.js');if(!s)return;
 e.querySelectorAll('.judge button').forEach(b=>b.classList.toggle('on',b.dataset.j===v));s.textContent=v||'';}
document.querySelectorAll('.card').forEach(e=>{pa(e);e.querySelectorAll('.judge button').forEach(b=>b.onclick=()=>{
 J[e.dataset.id]=b.dataset.j;localStorage.setItem('snk_scanrev',JSON.stringify(J));pa(e);uc();});});
function uc(){document.getElementById('jc').textContent=Object.keys(J).length;}
function fl(){const s=document.getElementById('fs').value,u=document.getElementById('fu').checked;
 document.querySelectorAll('.card').forEach(e=>{let o=true;if(s&&e.dataset.status!==s)o=false;if(u&&J[e.dataset.id])o=false;e.style.display=o?'':'none';});}
document.getElementById('fs').onchange=fl;document.getElementById('fu').onchange=fl;
document.getElementById('ex').onclick=()=>{let o='our_card_id,verdict\\n';for(const k in J)o+=k+','+J[k]+'\\n';
 const b=new Blob([o],{type:'text/csv'}),a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='snk_scanner_verdicts.csv';a.click();};uc();"""
page=f"""<!doctype html><html lang=ko><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>SNKRDUNK 스캐너 후보 검수</title><style>
*{{box-sizing:border-box}}body{{font-family:-apple-system,'Apple SD Gothic Neo',sans-serif;margin:0;background:#f6f8fa;color:#1f2328}}
.top{{position:sticky;top:0;background:#24292f;color:#fff;padding:10px 16px;z-index:9;display:flex;gap:12px;align-items:center;flex-wrap:wrap}}
.top b{{font-size:15px}}.top .st{{font-size:12px;opacity:.85}}.top button{{padding:5px 12px;border:0;border-radius:6px;background:#2da44e;color:#fff;cursor:pointer}}
.wrap{{max-width:1150px;margin:0 auto;padding:14px}}
.card{{background:#fff;border:1px solid #d0d7de;border-radius:10px;margin:12px 0;overflow:hidden}}
.hd{{display:flex;gap:10px;align-items:center;padding:8px 12px;border-bottom:1px solid #eaeef2;background:#fafbfc}}
.badge{{color:#fff;font-size:11px;font-weight:700;padding:3px 8px;border-radius:20px}}.nm{{font-weight:700}}
.cnt{{font-size:11px;color:#57606a}}.cid{{margin-left:auto;font-family:ui-monospace,monospace;font-size:10px;color:#8b949e}}
.body{{display:grid;grid-template-columns:1fr 1.1fr 1.2fr;gap:10px;padding:12px}}@media(max-width:840px){{.body{{grid-template-columns:1fr}}}}
.lbl{{font-size:11px;font-weight:700;color:#57606a;text-transform:uppercase;margin-bottom:6px}}
.big{{width:100%;max-width:210px;border-radius:8px;background:#f0f0f0;display:block}}
.snkbig img{{width:100%;max-width:210px;border-radius:8px;background:#f0f0f0;display:block}}
.snksm{{display:inline-block;width:70px;vertical-align:top;margin:3px;font-size:9px}}.snksm img{{width:68px;border-radius:4px}}
.cm{{font-size:12px;margin-top:5px;line-height:1.5}}.mono{{font-family:ui-monospace,monospace;font-size:11px;color:#57606a}}
.sc{{color:#1a7f37}}a{{color:#0969da;font-size:11px}}.others{{margin-top:8px}}
.t5wrap{{display:flex;gap:5px;flex-wrap:wrap;background:#f6f8fa;border-radius:8px;padding:6px}}
.t5{{width:60px;font-size:9px;text-align:center}}.t5 img{{width:58px;height:80px;object-fit:cover;border-radius:4px;border:2px solid transparent}}.t5.h img{{border-color:#1a7f37}}
.judge{{margin-top:10px;display:flex;gap:6px;flex-wrap:wrap;align-items:center}}.judge button{{padding:6px 12px;border:1px solid #d0d7de;border-radius:7px;background:#fff;cursor:pointer;font-size:13px}}
.judge button.on{{background:#0969da;color:#fff;border-color:#0969da}}.js{{font-size:12px;color:#57606a}}
</style></head><body>
<div class=top><b>SNKRDUNK 스캐너 후보 검수</b>
 <span class=st>등록후보 {len(cand)} · 고유카드 {len(by_card)} · 버킷[{esc(bstat)}]</span>
 <label>상태 <select id=fs><option value="">전체</option><option>HIGH_CONFIDENCE</option><option>IMAGE_MATCH_NEEDS_REVIEW</option><option>TOP5_NEEDS_REVIEW</option></select></label>
 <label><input type=checkbox id=fu> 미판정만</label><span class=st>판정 <b id=jc>0</b></span><button id=ex>CSV 내보내기</button></div>
<div class=wrap>{''.join(blocks)}</div><script>{JS}</script></body></html>"""
open(HTML_OUT,"w",encoding="utf-8").write(page)
print(f"[HTML] {HTML_OUT}")
