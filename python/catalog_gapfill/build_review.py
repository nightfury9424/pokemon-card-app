"""갭 검수 HTML 생성 — 전역 dedup(이미 보유 ref 제외) + 본세트/프로모 분리.
입력: /tmp/catalog.tsv(KO덤프), /tmp/gaps.tsv(scrydex크롤), scanner/data/ko_en_pokemon.json
출력: gaps_enriched.json, review.html
"""
import csv, json, html as H, collections, os

BASE = os.path.dirname(__file__)
EXCL = {'C', 'U', 'R', 'S', 'K', '', 'None', '●', '♦', '★', 'Shiny Rare'}

# 1. 전역 보유 jp ref (dedup 기준)
have = set()
for r in csv.reader(open('/tmp/catalog.tsv'), delimiter='\t'):
    if len(r) >= 3 and r[2].strip():
        have.add(r[2].strip())

# 2. pokedex# -> KO 이름
ko = json.load(open(os.path.join(BASE, '../../scanner/data/ko_en_pokemon.json')))
dex2ko = {i + 1: k for i, k in enumerate(ko.keys())}

# 3. gaps 정제 + 전역 dedup + 인리치
cards = []
dropped_dup = 0
for r in csv.reader(open('/tmp/gaps.tsv'), delimiter='\t'):
    if len(r) < 9:
        continue
    pname, n, ref, jpname, sup, subs, rar, rcode, dex = r
    if rcode in EXCL:
        continue
    if ref in have:                      # ★전역 dedup: 이미 보유
        dropped_dup += 1
        continue
    koname, conf = '', 'LOW'
    if dex:
        ids = [int(x) for x in dex.split(',') if x.strip().isdigit()]
        nm = [dex2ko.get(i) for i in ids if dex2ko.get(i)]
        if nm:
            koname = ' & '.join(nm)
            conf = 'HIGH' if len(nm) == 1 else 'MEDIUM'
    cards.append({
        'ref': ref, 'set': pname, 'num': n, 'jp': jpname, 'ko': koname,
        'rarity': rcode, 'sup': '서포터' if sup == 'トレーナー' else '포켓몬',
        'conf': conf, 'promo': (rcode == 'PROMO'),
        'img': f"https://images.scrydex.com/pokemon/{ref}/medium",
        'scrydex': f"https://scrydex.com/pokemon/cards/_/{ref}",
        'pc': f"https://pokemoncard.co.kr/cards?keyword={H.escape(koname or jpname)}",
        'status': 'PENDING',
    })

main = [c for c in cards if not c['promo']]
promo = [c for c in cards if c['promo']]
json.dump({'main': main, 'promo': promo}, open(os.path.join(BASE, 'gaps_enriched.json'), 'w'),
          ensure_ascii=False)
print(f"dedup 제외 {dropped_dup}장 / 본세트 {len(main)}(HIGH {sum(c['conf']=='HIGH' for c in main)}) + 프로모 {len(promo)}")

# 4. HTML
DATA_JS = json.dumps({'main': main, 'promo': promo}, ensure_ascii=False)
TPL = r'''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><title>카탈로그 갭 검수</title>
<style>
*{box-sizing:border-box;font-family:-apple-system,system-ui,sans-serif}
body{margin:0;background:#f4f5f7;color:#1a1a1a}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid #ddd;padding:10px 16px;z-index:10;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.tabs{display:flex;gap:8px;margin-bottom:8px}
.tab{padding:6px 16px;border-radius:20px;border:1px solid #ccc;background:#fff;cursor:pointer;font-weight:600;font-size:14px}
.tab.on{background:#2962ff;color:#fff;border-color:#2962ff}
.bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;font-size:13px}
select,input[type=text]{padding:5px 8px;border:1px solid #ccc;border-radius:6px;font-size:13px}
button{cursor:pointer;border:none;border-radius:6px;padding:6px 12px;font-weight:600;font-size:13px}
.btn-bulk{background:#2962ff;color:#fff}.btn-exp{background:#37474f;color:#fff}
.btn-keep{background:#e8f5e9;color:#2e7d32}.btn-rej{background:#ffebee;color:#c62828}
.stat{margin-left:auto;font-weight:700}
.grid{padding:14px;display:grid;grid-template-columns:repeat(auto-fill,minmax(290px,1fr));gap:12px}
.card{background:#fff;border:2px solid #eee;border-radius:10px;padding:10px;display:flex;gap:10px}
.card.KEEP{border-color:#66bb6a;background:#f1f8f2}.card.REJECT{border-color:#ef9a9a;opacity:.5}
.card img{width:90px;height:126px;object-fit:contain;background:#fafafa;border-radius:6px}
.meta{flex:1;min-width:0;font-size:12px;line-height:1.5}
.ko{font-size:15px;font-weight:700}.ko input{width:100%;font-size:14px;font-weight:700;margin-top:2px}
.badge{display:inline-block;padding:1px 7px;border-radius:10px;font-size:11px;font-weight:700;margin-right:4px}
.HIGH{background:#e8f5e9;color:#2e7d32}.MEDIUM{background:#fff8e1;color:#f57f17}.LOW{background:#ffebee;color:#c62828}.rar{background:#ede7f6;color:#5e35b1}
.lnk{color:#1565c0;text-decoration:none;font-size:11px;margin-right:8px}
.acts{margin-top:6px;display:flex;gap:6px}.muted{color:#888}
</style></head><body>
<header><div class="tabs">
 <div class="tab on" data-t="main" onclick="tab('main')">본세트 chase <span id="cm"></span></div>
 <div class="tab" data-t="promo" onclick="tab('promo')">프로모(KO검증필요) <span id="cp"></span></div></div>
<div class="bar">
 <select id="fset" onchange="render()"></select>
 <select id="fstat" onchange="render()"><option value="">전체상태</option><option>PENDING</option><option>KEEP</option><option>REJECT</option></select>
 <select id="fconf" onchange="render()"><option value="">전체신뢰도</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option></select>
 <input type="text" id="fq" placeholder="이름검색" oninput="render()" style="width:120px">
 <button class="btn-bulk" onclick="bulkKeep()">보이는 HIGH 전체 KEEP</button>
 <button class="btn-exp" onclick="exp()">KEEP 내보내기(JSON)</button>
 <span class="stat" id="stat"></span></div></header>
<div class="grid" id="grid"></div>
<script>
const DATA=__DATA__;let cur='main',LS='gapfill_v2';
const saved=JSON.parse(localStorage.getItem(LS)||'{}');
for(const k of ['main','promo'])DATA[k].forEach(c=>{const s=saved[c.ref];if(s){c.status=s.status||c.status;if(s.ko!=null)c.ko=s.ko;}});
function save(){const o={};for(const k of ['main','promo'])DATA[k].forEach(c=>{if(c.status!=='PENDING'||c._ed)o[c.ref]={status:c.status,ko:c.ko};});localStorage.setItem(LS,JSON.stringify(o));}
function tab(t){cur=t;document.querySelectorAll('.tab').forEach(e=>e.classList.toggle('on',e.dataset.t===t));buildSets();render();}
function buildSets(){const s=[...new Set(DATA[cur].map(c=>c.set))].sort();const el=document.getElementById('fset');el.innerHTML='<option value="">전체세트('+DATA[cur].length+')</option>'+s.map(x=>'<option>'+x+'</option>').join('');}
function setStatus(ref,st){const c=DATA[cur].find(x=>x.ref===ref);c.status=c.status===st?'PENDING':st;save();render();}
function editKo(ref,v){const c=DATA[cur].find(x=>x.ref===ref);c.ko=v;c._ed=1;save();}
function bulkKeep(){vis().forEach(c=>{if(c.conf==='HIGH')c.status='KEEP';});save();render();}
function vis(){const fs=fset.value,ft=fstat.value,fc=fconf.value,q=fq.value.trim();return DATA[cur].filter(c=>(!fs||c.set===fs)&&(!ft||c.status===ft)&&(!fc||c.conf===fc)&&(!q||(c.ko+c.jp).includes(q)));}
function render(){const v=vis();
 document.getElementById('grid').innerHTML=v.map(c=>`<div class="card ${c.status}"><img src="${c.img}" loading="lazy" onerror="this.style.opacity=.2"><div class="meta">
 <div class="ko">${c.ko?c.ko:`<input placeholder="KO이름 입력" oninput="editKo('${c.ref}',this.value)">`}</div>
 <div class="muted">${c.jp}</div><div><span class="badge rar">${c.rarity}</span><span class="badge ${c.conf}">${c.conf}</span> ${c.sup}</div>
 <div class="muted">${c.set} · ${c.num}</div>
 <div><a class="lnk" href="${c.scrydex}" target="_blank">scrydex↗</a><a class="lnk" href="${c.pc}" target="_blank">pokemoncard검색↗</a></div>
 <div class="acts"><button class="btn-keep" onclick="setStatus('${c.ref}','KEEP')">KEEP</button><button class="btn-rej" onclick="setStatus('${c.ref}','REJECT')">REJECT</button></div>
 </div></div>`).join('');
 const a=DATA[cur];document.getElementById('stat').textContent=`보임 ${v.length} | KEEP ${a.filter(c=>c.status==='KEEP').length} · REJECT ${a.filter(c=>c.status==='REJECT').length} · 대기 ${a.filter(c=>c.status==='PENDING').length}`;
 document.getElementById('cm').textContent=DATA.main.length;document.getElementById('cp').textContent=DATA.promo.length;}
function exp(){const out=[];for(const k of ['main','promo'])DATA[k].forEach(c=>{if(c.status==='KEEP')out.push({ref:c.ref,set:c.set,num:c.num,ko:c.ko,jp:c.jp,rarity:c.rarity,sup:c.sup,promo:c.promo});});
 const b=new Blob([JSON.stringify(out,null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='approved_'+new Date().toISOString().slice(0,10)+'.json';a.click();alert('KEEP '+out.length+'장 내보냄');}
buildSets();render();
</script></body></html>'''
open(os.path.join(BASE, 'review.html'), 'w').write(TPL.replace('__DATA__', DATA_JS))
print("review.html 재생성 완료")
