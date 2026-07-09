#!/usr/bin/env python3
"""검수 도구 v5 — 인터랙티브 (승인/제외/보류/매핑오류 + localStorage + JSON/CSV export). read-only."""
import json, collections

HI = {'RR','RRR','AR','SR','SAR','SSR','UR','HR','CSR','MUR','MA','CHR'}
CDN = "https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp"
jm = {c['code']: c for c in json.load(open('jp_match_preview.json'))}
res = {r['code']: r for r in json.load(open('/tmp/img_dedup_results.json'))}
rej = {o['code']: o for o in json.load(open('/tmp/rejudge.json'))}
rf = json.load(open('/tmp/resolve_final.json'))
resolved_ref = {o['code']: o['resolved_ref'] for o in rf['resolved']}
unres = {o['code']: o for o in rf['unresolved']}
sims = json.load(open('/tmp/crosslang_sims.json'))
prod_jp = {}; prod_en = {}
for line in open('/tmp/prod_refmap.csv'):
    p = (line.rstrip('\n').split('|') + ['']*4)[:4]
    cid, nm, jp, en = p
    if jp and not jp.startswith('NO_'): prod_jp[jp] = (cid, nm)
    if en and not en.startswith('NO_'): prod_en[en] = (cid, nm)

scope = [c for c in jm.values() if c.get('verdict') != 'EXCLUDE_JP' and c['ko_rarity'] in HI
         and (('포켓몬' in c['type']) or ('서포트' in c['type']))]

def classify(c):
    code = c['code']; jp = c.get('jp_ref') or ''; en = c.get('en_ref') or ''
    if (jp and (jp in prod_jp or jp in prod_en)) or (en and (en in prod_jp or en in prod_en)):
        return 'EXCLUDE_EXACT_REF'
    s = res.get(code, {}).get('score', 0)
    if s >= 0.75:
        o = rej.get(code, {})
        if o.get('s1', 0) >= 0.92 and o.get('nm_match') and o.get('rar_match') and o.get('margin', 0) >= 0.05:
            return 'EXCLUDE_SAME_ART_AUTO_CANDIDATE'
        return 'MANUAL_REVIEW'
    if code in resolved_ref or c.get('jp_ref'): return 'NEW_CANDIDATE'
    return 'UNRESOLVED'

records = []
for c in scope:
    code = c['code']; o = rej.get(code, {}); cls = classify(c)
    fref = c.get('jp_ref') or resolved_ref.get(code, '')
    rec = {
        'code': code, 'ko_name': c['ko_name'],
        'series': fref.split('-')[0] if fref else (c.get('series_jp_set') or '?'),
        'ko_set': c['ko_set_name'], 'ko_no': c['ko_collection_no'], 'rarity': c['ko_rarity'],
        'type': c['type'].split('|')[0].strip(), 'jp_ref': fref, 'en_ref': c.get('en_ref') or '',
        'resolved': code in resolved_ref,
        'ko_img': c.get('ko_image_url', ''), 'jp_img': c.get('jp_image_url') or c.get('en_image_url') or '',
        'cls': cls, 'match_cid': o.get('match_cid', ''), 'match_name': o.get('t1_name', ''),
        'match_rarity': o.get('t1_rar', ''),
        'prod_img': f"{CDN}/{o['match_cid']}.png" if o.get('match_cid') else '',
        's1': o.get('s1', ''), 's2': o.get('s2', ''), 'margin': o.get('margin', ''),
        'nm_match': o.get('nm_match'), 'rar_match': o.get('rar_match'),
        'unres_reason': unres.get(code, {}).get('reason', ''),
    }
    sm = sims.get(code, {})
    rec['jp_img'] = sm.get('jp_url') or rec['jp_img']
    rec['en_img'] = sm.get('en_url', '')
    rec['en_status'] = ('ok' if sm.get('en_loaded') else ('load_fail' if sm.get('has_en_ref') else 'no_ref'))
    rec['ko_jp'] = sm.get('ko_jp'); rec['ko_en'] = sm.get('ko_en'); rec['jp_en'] = sm.get('jp_en')
    if cls == 'EXCLUDE_EXACT_REF':
        jp = c.get('jp_ref') or ''; en = c.get('en_ref') or ''
        m = prod_jp.get(jp) or prod_en.get(en) or prod_jp.get(en) or prod_en.get(jp)
        if m:
            rec['match_cid'] = m[0]; rec['match_name'] = m[1]; rec['prod_img'] = f"{CDN}/{m[0]}.png"
    records.append(rec)

DATA_JSON = json.dumps(records, ensure_ascii=False)
print(f"records {len(records)} · series {len(set(r['series'] for r in records))}")
print(f"  분류: {dict(collections.Counter(r['cls'] for r in records))}")

HTML = r'''<!doctype html><html><head><meta charset=utf-8><title>시리즈 갭 검수 v6</title>
<style>
*{box-sizing:border-box}body{font-family:-apple-system,sans-serif;margin:0;background:#eceff1}
#bar{position:sticky;top:0;background:#1e272e;color:#fff;padding:8px 12px;z-index:20;display:flex;gap:10px;align-items:center;flex-wrap:wrap}
#bar select,#bar button{padding:5px 9px;font-size:13px;border-radius:4px;border:1px solid #555;background:#2f3640;color:#fff;cursor:pointer}
#bar button.on{background:#0984e3}
#prog{font-weight:bold;color:#ffd}
.dl{background:#00b894 !important}
.card{display:flex;gap:14px;background:#fff;margin:10px;padding:12px;border-radius:8px;box-shadow:0 1px 4px #0002;border-left:8px solid #ccc;align-items:flex-start}
.card.approve{border-left-color:#00b894;background:#eafaf3}
.card.exclude{border-left-color:#d63031;background:#fdeaea}
.card.hold{border-left-color:#fdcb6e;background:#fef9e7}
.card.mapping_error{border-left-color:#6c5ce7;background:#f0eefc}
.card.focus{outline:3px solid #0984e3}
.imgwrap{text-align:center;font-size:11px;color:#666}

.imgwrap img{width:185px;height:255px;object-fit:contain;background:#f5f5f5;border:1px solid #ddd;cursor:zoom-in;display:block}

.noimg{width:185px;height:255px;display:flex;align-items:center;justify-content:center;background:#f0f0f0;border:1px dashed #aaa;color:#999}
.info{flex:1;font-size:13px;min-width:240px}
.info b{font-size:16px}.info table{border-collapse:collapse;margin-top:6px}.info td{padding:1px 8px 1px 0;font-size:12px}
.tag{display:inline-block;padding:2px 7px;border-radius:10px;font-size:11px;color:#fff;margin-left:6px}
.btns{margin-top:10px;display:flex;gap:6px;flex-wrap:wrap}
.btns button{padding:8px 12px;font-size:13px;border-radius:5px;border:0;cursor:pointer;color:#fff;font-weight:bold}
.b-approve{background:#00b894}.b-exclude{background:#d63031}.b-hold{background:#f0a800}.b-map{background:#6c5ce7}
.cur{font-size:11px;color:#888;margin-top:4px}
.ok{color:#0a0;font-weight:bold}.no{color:#d00;font-weight:bold}
#modal{display:none;position:fixed;inset:0;background:#000d;z-index:99;justify-content:center;align-items:center}
#modal img{max-width:92%;max-height:92%}
.hint{font-size:11px;color:#aaa}
</style></head><body>
<div id=bar>
  <b>갭 검수 v6</b>
  <label>시리즈 <select id=sel></select></label>
  <button id=prev>◀ 이전</button><button id=next>다음 ▶</button>
  <span style="border-left:1px solid #555;padding-left:10px">필터</span>
  <button class=flt data-f=undecided>미판정</button>
  <button class=flt data-f=all>전체</button>
  <button class=flt data-f=approve>승인</button>
  <button class=flt data-f=exclude>제외</button>
  <button class=flt data-f=hold>보류</button>
  <button class=flt data-f=mapping_error>매핑오류</button>
  <span id=prog></span>
  <button class=dl id=dljson>JSON</button><button class=dl id=dlcsv>CSV</button>
  <span class=hint>키: A승인 E제외 H보류 X매핑오류 ←→이동</span>
</div>
<div id=list></div>
<div id=modal><img id=mimg></div>
<script>
const DATA=__DATA__;
const PRIO=['m3_ja','m4_ja'];
const CLSCOLOR={NEW_CANDIDATE:'#0984e3',MANUAL_REVIEW:'#e17055',EXCLUDE_SAME_ART_AUTO_CANDIDATE:'#d63031',EXCLUDE_EXACT_REF:'#636e72',UNRESOLVED:'#b2bec3'};
let state=JSON.parse(localStorage.getItem('gapReviewV6')||'{}');
let curSeries=null, curFilter='undecided', focusIdx=0;

function seriesList(){
  const c={}; DATA.forEach(d=>c[d.series]=(c[d.series]||0)+1);
  let ss=Object.keys(c);
  ss.sort((a,b)=>{let pa=PRIO.indexOf(a),pb=PRIO.indexOf(b); if(pa<0)pa=99; if(pb<0)pb=99; if(pa!=pb)return pa-pb; return c[b]-c[a];});
  return ss.map(s=>[s,c[s]]);
}
function save(){localStorage.setItem('gapReviewV6',JSON.stringify(state));}
function setDec(code,dec,note){ state[code]=state[code]||{}; state[code].decision=dec; if(note!=null)state[code].note=note; save(); render(); }
function visible(){
  let cards=DATA.filter(d=>d.series===curSeries);
  if(curFilter==='undecided') cards=cards.filter(d=>!state[d.code]||!state[d.code].decision);
  else if(curFilter!=='all') cards=cards.filter(d=>state[d.code]&&state[d.code].decision===curFilter);
  return cards;
}
function imgCell(url,label){
  if(!url) return `<div class=imgwrap><div class=noimg>이미지 없음</div>${label}</div>`;
  return `<div class=imgwrap><img src="${url}" onclick="zoom('${url}')"><div>${label}</div></div>`;
}
function enCell(d){
  if(d.en_status==='ok') return imgCell(d.en_img,'EN 후보 ('+(d.en_jp_ref||'')+')');
  if(d.en_status==='load_fail') return '<div class=imgwrap><div class=noimg>EN 이미지<br>로딩 실패</div>EN 후보</div>';
  return '<div class=imgwrap><div class=noimg style="color:#bbb">EN 후보 없음</div>EN ref 없음</div>';
}
function evidence(d){
  const sv=x=>x==null?'<span style=color:#bbb>-</span>':(x>=0.88?'<span class=ok>'+x+'</span>':(x>=0.78?'<span style=color:#e80>'+x+'</span>':'<span class=no>'+x+'</span>'));
  let xl=`<tr><td>교차언어 일러스트</td><td>KO↔JP ${sv(d.ko_jp)} · KO↔EN ${sv(d.ko_en)} · JP↔EN ${sv(d.jp_en)}</td></tr>`;
  let dup=`<tr><td>기존 prod 중복</td><td>${d.cls==='EXCLUDE_EXACT_REF'?'<span class=no>exact-ref 존재</span>':'exact-ref 없음'} · KO↔prod img ${sv(d.s1||null)}</td></tr>`;
  let _base=xl+dup;
  if(['MANUAL_REVIEW','EXCLUDE_SAME_ART_AUTO_CANDIDATE','EXCLUDE_EXACT_REF'].includes(d.cls)){
    let nm=d.nm_match===true?'<span class=ok>O</span>':(d.nm_match===false?'<span class=no>X</span>':'-');
    let rr=d.rar_match===true?'<span class=ok>O</span>':(d.rar_match===false?'<span class=no>X</span>':'-');
    return _base+`<tr><td>prod 매칭</td><td>${d.match_name||'-'} (${d.match_rarity||'?'}) <code>${(d.match_cid||'').slice(0,16)}</code></td></tr>
    <tr><td>score1 / score2</td><td><b>${d.s1}</b> / ${d.s2} · margin <b>${d.margin}</b></td></tr>
    <tr><td>이름 / 레어도 일치</td><td>${nm} / ${rr}</td></tr>`;
  }
  if(d.cls==='UNRESOLVED') return _base+`<tr><td>미해결 사유</td><td>${d.unres_reason}</td></tr>`;
  return _base;
}
function render(){
  const cards=visible();
  if(focusIdx>=cards.length)focusIdx=Math.max(0,cards.length-1);
  document.getElementById('list').innerHTML = cards.map((d,i)=>{
    const dec=(state[d.code]||{}).decision||'';
    const prodCell=(d.prod_img||d.match_cid)?imgCell(d.prod_img,'기존 prod'):'';
    return `<div class="card ${dec} ${i===focusIdx?'focus':''}" id=card${i}>
      ${imgCell(d.ko_img,'KO 원본')}
      ${imgCell(d.jp_img,'JP 후보'+(d.resolved?' (resolved)':''))}
      ${enCell(d)}
      ${prodCell}
      <div class=info>
        <b>${d.ko_name}</b> <span class=tag style="background:${CLSCOLOR[d.cls]}">${d.cls}</span>
        <table>
        <tr><td>시리즈/번호</td><td>${d.ko_set} · #${d.ko_no}</td></tr>
        <tr><td>레어도/타입</td><td>${d.rarity} · ${d.type}</td></tr>
        <tr><td>JP ref</td><td><code>${d.jp_ref||'<b style=color:red>미확정</b>'}</code> ${d.resolved?'<span class=ok>resolved</span>':''}</td></tr>
        <tr><td>EN ref</td><td><code>${d.en_ref||'-'}</code></td></tr>
        ${evidence(d)}
        </table>
        <div class=btns>
          <button class=b-approve onclick="setDec('${d.code}','approve')">추가 승인 (A)</button>
          <button class=b-exclude onclick="setDec('${d.code}','exclude')">동일일러스트 제외 (E)</button>
          <button class=b-hold onclick="setDec('${d.code}','hold')">보류 (H)</button>
          <button class=b-map onclick="setDec('${d.code}','mapping_error')">매핑오류 (X)</button>
        </div>
        <div class=cur>현재 판정: <b>${dec?dec.toUpperCase():'미판정'}</b></div>
      </div></div>`;
  }).join('') || '<p style="padding:20px">이 필터에 카드 없음</p>';
  const total=DATA.length, done=DATA.filter(d=>state[d.code]&&state[d.code].decision).length;
  const sTotal=DATA.filter(d=>d.series===curSeries).length;
  const sDone=DATA.filter(d=>d.series===curSeries&&state[d.code]&&state[d.code].decision).length;
  document.getElementById('prog').textContent=`[${curSeries}] ${sDone}/${sTotal} · 전체 ${done}/${total}`;
  document.querySelectorAll('.flt').forEach(b=>b.classList.toggle('on',b.dataset.f===curFilter));
  const fc=document.getElementById('card'+focusIdx); if(fc)fc.scrollIntoView({block:'nearest'});
}
function zoom(u){document.getElementById('mimg').src=u;document.getElementById('modal').style.display='flex';}
document.getElementById('modal').onclick=()=>document.getElementById('modal').style.display='none';
function buildSel(){
  const sel=document.getElementById('sel');
  sel.innerHTML=seriesList().map(([s,n])=>`<option value="${s}">${s} (${n})</option>`).join('');
  curSeries=seriesList()[0][0]; sel.value=curSeries;
  sel.onchange=()=>{curSeries=sel.value;focusIdx=0;render();};
}
document.getElementById('prev').onclick=()=>{const ss=seriesList().map(x=>x[0]);let i=ss.indexOf(curSeries);if(i>0){curSeries=ss[i-1];document.getElementById('sel').value=curSeries;focusIdx=0;render();}};
document.getElementById('next').onclick=()=>{const ss=seriesList().map(x=>x[0]);let i=ss.indexOf(curSeries);if(i<ss.length-1){curSeries=ss[i+1];document.getElementById('sel').value=curSeries;focusIdx=0;render();}};
document.querySelectorAll('.flt').forEach(b=>b.onclick=()=>{curFilter=b.dataset.f;focusIdx=0;render();});
function dl(name,content,type){const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([content],{type}));a.download=name;a.click();}
document.getElementById('dljson').onclick=()=>{
  const out=DATA.map(d=>({code:d.code,series:d.series,ko_name:d.ko_name,rarity:d.rarity,jp_ref:d.jp_ref,original_classification:d.cls,reviewer_decision:(state[d.code]||{}).decision||'',reviewer_note:(state[d.code]||{}).note||''}));
  dl('gap_review_decisions.json',JSON.stringify(out,null,1),'application/json');};
document.getElementById('dlcsv').onclick=()=>{
  const hdr=['code','series','ko_name','rarity','jp_ref','original_classification','reviewer_decision','reviewer_note'];
  const esc=v=>'"'+String(v==null?'':v).replace(/"/g,'""')+'"';
  const lines=[hdr.join(',')].concat(DATA.map(d=>[d.code,d.series,d.ko_name,d.rarity,d.jp_ref,d.cls,(state[d.code]||{}).decision||'',(state[d.code]||{}).note||''].map(esc).join(',')));
  dl('gap_review_decisions.csv',lines.join('\n'),'text/csv');};
document.addEventListener('keydown',e=>{
  if(e.target.tagName==='SELECT'||e.target.tagName==='INPUT')return;
  const cards=visible(); const d=cards[focusIdx];
  const k=e.key.toLowerCase();
  if(k==='a'&&d)setDec(d.code,'approve');
  else if(k==='e'&&d)setDec(d.code,'exclude');
  else if(k==='h'&&d)setDec(d.code,'hold');
  else if(k==='x'&&d)setDec(d.code,'mapping_error');
  else if(e.key==='ArrowRight'){focusIdx=Math.min(cards.length-1,focusIdx+1);render();}
  else if(e.key==='ArrowLeft'){focusIdx=Math.max(0,focusIdx-1);render();}
});
buildSel(); render();
</script></body></html>'''

HTML = HTML.replace('__DATA__', DATA_JSON)
open('series_gap_final_review_v6.html', 'w').write(HTML)
print(f"series_gap_final_review_v6.html 생성 ({len(HTML)//1024}KB)")
