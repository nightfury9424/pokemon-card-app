#!/usr/bin/env python3
"""KO기준 재매칭 제안 → 승인 검수 HTML. 자동반영 X. 사용자가 JP/EN 채택 승인 후 export."""
import json
D=json.load(open("/tmp/rematch_proposals.json"))
def simg(ref): return f"https://images.scrydex.com/pokemon/{ref}/medium"
def sc(x):
    if x is None: return '<span style=color:#bbb>-</span>'
    c='#0a0' if x>=0.88 else ('#e80' if x>=0.80 else '#d00')
    return f'<span style="color:{c};font-weight:bold">{x}</span>'
rows=[]
for d in D:
    jp_cur=d['jp_ref']; jpcs=d['cur_jp_score']; jpp=d.get('jp_prop'); enp=d.get('en_prop')
    # JP 셀: 현재 + (있으면)제안
    jp_html=f'<div class=cell><img loading=lazy src="{simg(jp_cur)}" onclick="z(this.src)"><div>JP 현재<br><code>{jp_cur}</code><br>KO↔JP {sc(jpcs)}</div></div>'
    if jpp:
        jp_html+=f'<div class="cell prop"><img loading=lazy src="{simg(jpp["ref"])}" onclick="z(this.src)"><div>★JP 제안<br><code>{jpp["ref"]}</code><br>KO↔JP {sc(jpp["score"])}</div></div>'
    en_html=(f'<div class="cell prop"><img loading=lazy src="{enp["img"]}" onclick="z(this.src)"><div>★EN 제안<br><code>{enp["ref"]}</code><br>EN↔JP {sc(enp["score"])}·EN↔KO {sc(enp.get("ko"))}</div></div>' if enp
             else '<div class=cell><div class=noimg>EN 후보<br>못 찾음</div></div>')
    flag=''
    if jpcs<0.78: flag='<span class=tag style=background:#c0392b>JP 명백오류 의심</span>'
    elif jpcs<0.85: flag='<span class=tag style=background:#e67e22>JP 경계(이미지 직접확인)</span>'
    rows.append(f'''<div class="card" id="c{len(rows)}" data-code="{d['code']}" data-defjp="{jpp['ref'] if jpp else jp_cur}" data-en="{enp['ref'] if enp else ''}">
  <div class=imgs><div class=cell><img loading=lazy src="{d['ko_img']}" onclick="z(this.src)"><div>KO 원본(진실)</div></div>{jp_html}{en_html}</div>
  <div class=info><b>{d['ko_name']}</b> <span class=tag style=background:#555>{d['rarity']}</span> {flag}
    <div class=meta>{d['ko_set']} #{d.get('ko_no','')} · 교차 KO↔JP {sc(d.get('ko_jp'))} KO↔EN {sc(d.get('ko_en'))}</div>
    <div class=choose>JP 채택: <label><input type=radio name=jp{len(rows)} value="{jp_cur}" {'checked' if not jpp else ''}>현재 {jp_cur}</label>
      {'<label><input type=radio name=jp'+str(len(rows))+' value="'+jpp['ref']+'" checked>★제안 '+jpp['ref']+'</label>' if jpp else ''}</div>
    <div class=choose>EN 채택: <label><input type=checkbox class=enck {'checked' if enp else 'disabled'}>{enp['ref'] if enp else '(없음→NO_EN)'}</label></div>
    <div class=btns><button class=ap onclick="dec(this,'approve')">승인 (A)</button>
      <button class=hd onclick="dec(this,'hold')">보류 (H)</button>
      <button class=rj onclick="dec(this,'reject')">거부 (X)</button></div>
    <div class=cur>판정: <b class= st>미판정</b></div>
  </div></div>''')
HTML=f'''<!doctype html><html><head><meta charset=utf-8><title>KO기준 JP·EN 재매칭 검수</title><style>
*{{box-sizing:border-box}}body{{font-family:-apple-system,sans-serif;background:#eceff1;margin:0}}
#bar{{position:sticky;top:0;background:#1e272e;color:#fff;padding:10px 14px;z-index:9;display:flex;gap:12px;align-items:center}}
#bar button{{padding:6px 11px;border-radius:5px;border:0;background:#0984e3;color:#fff;font-weight:bold;cursor:pointer}}
.card{{background:#fff;margin:10px;padding:12px;border-radius:8px;box-shadow:0 1px 4px #0002;border-left:8px solid #ccc}}
.card.approve{{border-left-color:#00b894;background:#eafaf3}}.card.hold{{border-left-color:#f0a800;background:#fef9e7}}.card.reject{{border-left-color:#d63031;background:#fdeaea}}
.imgs{{display:flex;gap:10px;flex-wrap:wrap}}.cell{{text-align:center;font-size:11px;color:#555}}
.cell img{{width:165px;height:228px;object-fit:contain;background:#f5f5f5;border:1px solid #ddd;cursor:zoom-in;display:block}}
.cell.prop img{{border:2px solid #0984e3}}.noimg{{width:165px;height:228px;display:flex;align-items:center;justify-content:center;background:#f0f0f0;border:1px dashed #aaa;color:#999}}
.info{{margin-top:10px}}.info b{{font-size:16px}}.meta{{font-size:12px;color:#666;margin:4px 0}}.choose{{font-size:13px;margin:5px 0}}
.tag{{display:inline-block;padding:2px 8px;border-radius:10px;font-size:11px;color:#fff;margin-left:4px}}
.btns{{margin-top:8px;display:flex;gap:6px}}.btns button{{padding:7px 13px;border-radius:5px;border:0;color:#fff;font-weight:bold;cursor:pointer}}
.ap{{background:#00b894}}.hd{{background:#f0a800}}.rj{{background:#d63031}}.cur{{font-size:12px;color:#888;margin-top:5px}}
#m{{display:none;position:fixed;inset:0;background:#000d;z-index:99;justify-content:center;align-items:center}}#m img{{max-width:92%;max-height:92%}}
</style></head><body>
<div id=bar><b>KO기준 JP·EN 재매칭 검수 ({len(D)}장)</b><span id=prog></span>
  <button onclick="exp()">JSON export</button><span style=font-size:12px;color:#aaa>A승인 H보류 X거부 ←→이동</span></div>
{''.join(rows)}
<div id=m onclick="this.style.display='none'"><img></div>
<script>
let st=JSON.parse(localStorage.getItem('rematchV1')||'{{}}'),fi=0;
const cards=[...document.querySelectorAll('.card')];
function z(s){{document.querySelector('#m img').src=s;document.getElementById('m').style.display='flex';}}
function save(){{localStorage.setItem('rematchV1',JSON.stringify(st));prog();}}
function dec(btn,d){{const c=btn.closest('.card');const jp=c.querySelector('input[type=radio]:checked')?.value||c.dataset.defjp;
  const en=c.querySelector('.enck').checked?c.dataset.en:'';st[c.dataset.code]={{status:d,jp:jp,en:en}};
  c.className='card '+d;c.querySelector('.st').textContent=d.toUpperCase();save();}}
function prog(){{const n=Object.values(st).filter(x=>x.status).length;document.getElementById('prog').textContent=` ${{n}}/${{cards.length}} 판정`;}}
function exp(){{const o=cards.map(c=>({{code:c.dataset.code,...(st[c.dataset.code]||{{status:'',jp:c.dataset.defjp,en:c.dataset.en}})}}));
  const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([JSON.stringify(o,null,2)],{{type:'application/json'}}));a.download='rematch_decisions.json';a.click();}}
document.addEventListener('keydown',e=>{{if(e.target.tagName==='INPUT')return;const c=cards[fi];const k=e.key.toLowerCase();
  if(k==='a')c.querySelector('.ap').click();else if(k==='h')c.querySelector('.hd').click();else if(k==='x')c.querySelector('.rj').click();
  else if(e.key==='ArrowDown'||e.key==='ArrowRight'){{fi=Math.min(cards.length-1,fi+1);cards[fi].scrollIntoView({{block:'center'}});}}
  else if(e.key==='ArrowUp'||e.key==='ArrowLeft'){{fi=Math.max(0,fi-1);cards[fi].scrollIntoView({{block:'center'}});}}}});
// restore
cards.forEach(c=>{{const s=st[c.dataset.code];if(s&&s.status){{c.className='card '+s.status;c.querySelector('.st').textContent=s.status.toUpperCase();}}}});prog();
</script></body></html>'''
open("/Users/fury/pokemon-card-app/python/catalog_gapfill/kotruth_rematch_review.html","w").write(HTML)
print(f"  kotruth_rematch_review.html 생성 ({len(D)}장)")
