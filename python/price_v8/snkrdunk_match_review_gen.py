"""SNKRDUNK ↔ PokeFolio 매칭 검수 HTML 생성기 (Stage-1).
입력: snkrdunk_to_pokefolio_match_candidates.csv  (apparel_id-primary)
출력: snkrdunk_to_pokefolio_match_review.html  — SNKRDUNK img | PokeFolio img 나란히 + 클릭 판정 + CSV export.
★로컬 전용. SNKRDUNK 이미지는 probe 가 images/snkrdunk/{apparel_id}.jpg 로 캐시(미수집=placeholder).
 PokeFolio 이미지는 scanner/data/cards/{card_id}_jp.png 에서 images/pokefolio/ 로 복사.
"""
import csv, os, shutil, sys, html

BASE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(BASE, "..", ".."))
PF_SRC = os.path.join(REPO, "scanner", "data", "cards")  # {card_id}_jp.png


def stage_pokefolio_image(card_id, out_dir):
    """우리 카드 jp 이미지를 검수폴더로 복사. 없으면 en/ko 폴백."""
    os.makedirs(out_dir, exist_ok=True)
    for suf in ("_jp.png", "_en.png", "_ko.png"):
        src = os.path.join(PF_SRC, f"{card_id}{suf}")
        if os.path.exists(src):
            dst = os.path.join(out_dir, f"{card_id}.png")
            if not os.path.exists(dst):
                shutil.copy(src, dst)
            return f"images/pokefolio/{card_id}.png"
    return None


CELL = """<tr data-aid="{aid}">
  <td class=s><div class=cap>SNKRDUNK</div>{snk_img}
    <div class=meta>aid <b>{aid}</b><br>{title}<br>set {set} / no {num} / {rar}<br><a href="{url}" target=_blank>detail</a></div></td>
  <td class=sc>img <b>{isc}</b><br>set#match {snm}<br>rarity {rm}<br>final <b>{fsc}</b><br><span class=st>{auto}</span></td>
  <td class=p><div class=cap>PokeFolio 후보</div>{pf_img}
    <div class=meta>{cid}<br>{name_ko} / {name_jp}<br>{code} · {prar}</div></td>
  <td class=btn>
    <button onclick="pick('{aid}','MATCH_HIGH',this)">HIGH</button>
    <button onclick="pick('{aid}','MATCH_MEDIUM',this)">MED</button>
    <button onclick="pick('{aid}','NEEDS_MANUAL_MATCH',this)">MANUAL</button>
    <button onclick="pick('{aid}','MISMATCH_CARD',this)">MISMATCH</button>
    <div class=dec id="d_{aid}"></div></td>
</tr>"""

PAGE = """<!doctype html><meta charset=utf-8><title>SNKRDUNK ↔ PokeFolio 검수</title>
<style>body{{font:13px -apple-system,sans-serif;background:#111;color:#ddd;margin:16px}}
table{{border-collapse:collapse;width:100%}}td{{border:1px solid #333;padding:8px;vertical-align:top}}
img{{width:150px;border-radius:6px;display:block}}.ph{{width:150px;height:210px;background:#222;border:1px dashed #555;
display:flex;align-items:center;justify-content:center;color:#777;text-align:center;font-size:11px;border-radius:6px}}
.cap{{font-weight:700;margin-bottom:4px;color:#9cf}}.meta{{margin-top:6px;font-size:11px;color:#aaa;line-height:1.5}}
.sc{{font-size:11px;color:#bbb;width:90px}}.st{{color:#fc6}}.btn button{{display:block;width:100%;margin:3px 0;padding:6px;
cursor:pointer;border:0;border-radius:4px;background:#2a2a2a;color:#ddd}}.btn button:hover{{background:#3a5}}
.dec{{margin-top:6px;font-weight:700;color:#6f6}}a{{color:#7af}}#bar{{position:sticky;top:0;background:#111;padding:8px 0;z-index:9}}
button#ex{{background:#3a6;color:#fff;padding:8px 16px;font-weight:700;border:0;border-radius:6px;cursor:pointer}}</style>
<div id=bar><b>SNKRDUNK ↔ PokeFolio 매칭 검수</b> &nbsp; {n}행 &nbsp;
<button id=ex onclick=exportCsv()>판정 CSV export</button> <span id=cnt></span></div>
<table><tr><th>SNKRDUNK</th><th>점수</th><th>PokeFolio</th><th>판정</th></tr>
{rows}</table>
<script>
const D={{}};
function pick(aid,st,el){{D[aid]=st;document.getElementById('d_'+aid).textContent=st;
 el.parentElement.querySelectorAll('button').forEach(b=>b.style.background='#2a2a2a');el.style.background='#3a6';
 document.getElementById('cnt').textContent=Object.keys(D).length+' 판정됨';}}
function exportCsv(){{let r=[['apparel_id','match_status']];for(const k in D)r.push([k,D[k]]);
 const c=r.map(x=>x.join(',')).join('\\n');const b=new Blob([c],{{type:'text/csv'}});
 const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='snkrdunk_to_pokefolio_match_review.csv';a.click();}}
</script>"""


def gen(cand_csv: str, out_html: str, img_dir: str):
    rows = []
    n = 0
    if os.path.exists(cand_csv):
        for r in csv.DictReader(open(cand_csv)):
            n += 1
            aid = r.get("apparel_id", "")
            snk_path = r.get("snkrdunk_image_path", "")
            snk_img = (f'<img src="{html.escape(snk_path)}">' if snk_path and os.path.exists(os.path.join(os.path.dirname(out_html), snk_path))
                       else '<div class=ph>SNKRDUNK<br>이미지<br>(probe 수집 대기)</div>')
            cid = r.get("candidate_card_id", "")
            pf_rel = stage_pokefolio_image(cid, img_dir) if cid else None
            pf_img = (f'<img src="{pf_rel}">' if pf_rel else '<div class=ph>PokeFolio<br>이미지 없음</div>')
            rows.append(CELL.format(aid=html.escape(aid), snk_img=snk_img,
                title=html.escape(r.get("snkrdunk_title", "")), set=html.escape(r.get("candidate_set", "")),
                num=html.escape(r.get("card_number_match", "")), rar=html.escape(r.get("rarity_match", "")),
                url=html.escape(r.get("snkrdunk_image_url", "#")), isc=r.get("image_similarity_score", "—"),
                snm=r.get("set_code_match", "—"), rm=r.get("rarity_match", "—"), fsc=r.get("final_match_score", "—"),
                auto=html.escape(r.get("match_status", "")), cid=html.escape(cid),
                name_ko=html.escape(r.get("name_ko", "")), name_jp=html.escape(r.get("name_jp", "")),
                code=html.escape(r.get("official_card_code", "")), prar=html.escape(r.get("rarity_code", "")), pf_img=pf_img))
    open(out_html, "w").write(PAGE.format(n=n, rows="\n".join(rows)))
    print(f"[review HTML] {out_html} ({n}행)")


if __name__ == "__main__":
    base = sys.argv[1] if len(sys.argv) > 1 else "/tmp/price_v8_snkrdunk_stage1_20260619"
    gen(os.path.join(base, "snkrdunk_to_pokefolio_match_candidates.csv"),
        os.path.join(base, "snkrdunk_to_pokefolio_match_review.html"),
        os.path.join(base, "images", "pokefolio"))
