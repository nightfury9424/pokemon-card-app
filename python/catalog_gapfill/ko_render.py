"""ko_master.json → KO-우선 검수 HTML. KO 칸=pokemoncard 공식 이미지만, scrydex는 JP/EN 칸 전용."""
import json, os
P = os.path.dirname(os.path.abspath(__file__))
DATA = json.dumps(json.load(open(os.path.join(P, 'ko_master.json'))), ensure_ascii=False)
TPL = r'''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><title>KO 공식 master 검수 (KO→JP/EN)</title>
<style>
*{box-sizing:border-box;font-family:-apple-system,system-ui,sans-serif}
body{margin:0;background:#f4f5f7;color:#1a1a1a;font-size:13px}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid #ddd;padding:10px 16px;z-index:10;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
select,input{padding:5px 8px;border:1px solid #ccc;border-radius:6px;font-size:13px}
.seg{display:inline-flex;border:1px solid #ccc;border-radius:6px;overflow:hidden}
.seg button{border:none;background:#fff;padding:5px 12px;cursor:pointer;font-weight:600}.seg button.on{background:#37474f;color:#fff}
h1{font-size:15px;margin:0 0 8px}.stat{margin-left:auto;font-weight:700}
.grid{padding:14px;display:grid;grid-template-columns:1fr;gap:12px;max-width:1100px;margin:0 auto}
.card{background:#fff;border:2px solid #66bb6a;border-radius:12px;padding:12px}
.hd{display:flex;align-items:center;gap:8px;margin-bottom:8px}.hd .nm{font-size:16px;font-weight:800}
.cols{display:flex;gap:10px;flex-wrap:wrap}
.col{flex:1;min-width:210px;border:1px solid #eee;border-radius:8px;padding:8px}
.col.ko{background:#f1f6ff}.col.jp{background:#fff8f1}.col.en{background:#f3fbf3}
.col .lbl{font-size:11px;font-weight:800;color:#555;margin-bottom:5px}
.col img{width:100%;max-width:160px;height:215px;object-fit:contain;background:#fff;border-radius:6px;display:block;margin:0 auto 6px}
.pending{height:215px;display:flex;align-items:center;justify-content:center;background:#fafafa;border:1px dashed #bbb;border-radius:6px;color:#999;font-weight:700;margin-bottom:6px;text-align:center;padding:8px}
.id{font-size:12px;line-height:1.55}.refs{font-family:ui-monospace,Menlo,monospace;font-size:11px;color:#1565c0;word-break:break-all}
.badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:800}
.v-ADD{background:#e8f5e9;color:#2e7d32}.rar{background:#ede7f6;color:#5e35b1}.code{background:#eceff1;color:#455a64;font-family:ui-monospace,Menlo,monospace}
.muted{color:#888}.lnk{color:#1565c0;text-decoration:none}
</style></head><body>
<header><h1>KO 공식 master 검수 — pokemoncard 한국발매분 (KO-verified) · prod 코드대조 신규</h1>
<div class="bar">
 <select id="fset" onchange="render()"></select>
 <select id="frar" onchange="render()"></select>
 <input type="text" id="fq" placeholder="이름검색" oninput="render()" style="width:140px">
 <span class="stat" id="stat"></span></div></header>
<div class="grid" id="grid"></div>
<script>
const DATA=__DATA__;
const esc=s=>(s==null?'':(''+s)).replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));
const imgEl=(u,oe)=>u?`<img src="${esc(u)}" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'pending',textContent:'이미지 로드 실패'}))">`:`<div class="pending">${oe||'없음'}</div>`;
function init(){const sets=[...new Set(DATA.map(c=>c.ko_set_name))].sort(),rars=[...new Set(DATA.map(c=>c.ko_rarity))].sort();
 fset.innerHTML='<option value="">전체세트('+DATA.length+')</option>'+sets.map(x=>'<option>'+esc(x)+'</option>').join('');
 frar.innerHTML='<option value="">전체레어도</option>'+rars.map(x=>'<option>'+esc(x)+'</option>').join('');}
function vis(){const s=fset.value,r=frar.value,q=fq.value.trim();
 return DATA.filter(c=>(!s||c.ko_set_name===s)&&(!r||c.ko_rarity===r)&&(!q||(c.ko_name+(c.jp_name||'')).includes(q)));}
function card(c){
 const ko=`<div class="col ko"><div class="lbl">KO 공식 (pokemoncard)</div>${imgEl(c.ko_image_url)}
   <div class="id"><b>${esc(c.ko_name)}</b><br>${esc(c.ko_set_name)}<br>번호 ${esc(c.ko_collection_no)} · <span class="badge rar">${esc(c.ko_rarity)}</span>
   <br><span class="refs">${esc(c.code)}</span><br><a class="lnk" href="${esc(c.ko_detail_url)}" target="_blank">pokemoncard 상세↗</a></div></div>`;
 const jp=`<div class="col jp"><div class="lbl">JP 후보 <span class="muted">${esc(c.jp_conf||'')}</span></div>${c.jp_ref?imgEl(c.jp_image_url):`<div class="pending">JP 미매칭<br>(다음 단계)</div>`}
   <div class="id">${c.jp_ref?`<b>${esc(c.jp_name)}</b><br><span class="refs">${esc(c.jp_ref)}</span>`:'<span class="muted">scrydex JP 매칭 대기</span>'}</div></div>`;
 const en=`<div class="col en"><div class="lbl">EN 후보 <span class="muted">${esc(c.en_conf||'')}</span></div>${c.en_ref?imgEl(c.en_image_url):`<div class="pending">EN 미매칭<br>(다음 단계)</div>`}
   <div class="id">${c.en_ref?`<b>${esc(c.en_name)}</b><br><span class="refs">${esc(c.en_ref)}</span>`:'<span class="muted">scrydex EN 매칭 대기</span>'}</div></div>`;
 return `<div class="card"><div class="hd"><span class="nm">${esc(c.ko_name)}</span>
   <span class="badge v-${c.verdict}">${c.verdict}</span><span class="badge code">${esc(c.code)}</span>
   <span class="muted">${esc(c.type)}</span></div><div class="cols">${ko}${jp}${en}</div></div>`;}
function render(){const v=vis();grid.innerHTML=v.map(card).join('');
 stat.textContent=`보임 ${v.length} / 전체 ${DATA.length} (전부 KO-verified ADD 후보)`;}
init();render();
</script></body></html>'''
open(os.path.join(P, 'ko_review.html'), 'w').write(TPL.replace('__DATA__', DATA))
print('→ ko_review.html 렌더 완료')
