"""갭 후보에 scrydex 가격 enrich + 가치순 review 렌더.
  python enrich_and_render.py main          # main 가격 fetch + 렌더
  python enrich_and_render.py promo          # promo
  python enrich_and_render.py main --render  # fetch 스킵, 기존 jp_krw로 렌더만
가격 = scrydex JP raw(USD)×환율 → 예상KO = ×frozen 레어도비율(근사, 실모델은 HIT/앵커 별도).
"""
import sys, types, json, time, os
from concurrent.futures import ThreadPoolExecutor, as_completed

# config 스텁 (실 config.py는 prod 전용) — parser만 재사용
cfg = types.ModuleType('config'); cfg.DB_CONFIG = {}
cfg.HEADERS = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
sys.modules['config'] = cfg
sys.path.insert(0, '/Users/fury/pokemon-card-app/python')
from price_scrydex import fetch_html, parse_history  # noqa

USD_FX = 1517  # prod 실측 (287041/189.22), 갱신 시 수정
FROZEN = {'MUR': 0.441648, 'HR': 0.10462, 'CSR': 0.617049, 'UR': 0.253425, 'SR': 0.162331, 'SAR': 0.275568}
GHIT = 0.249156
P = os.path.dirname(os.path.abspath(__file__))
SECTION = sys.argv[1] if len(sys.argv) > 1 else 'main'
RENDER_ONLY = '--render' in sys.argv

d = json.load(open(os.path.join(P, 'gaps_enriched.json')))


def fetch_one(c):
    try:
        html = fetch_html(c['ref'])
        if not html:
            return c['ref'], None
        raw, p10, p9, iskrw, isjpy = parse_history(html, is_jp=True, jpy_krw=9.1)
        if not raw:
            return c['ref'], None
        v = raw[-1][1]
        return c['ref'], (round(v) if iskrw else round(v * USD_FX))
    except Exception:
        return c['ref'], None


if not RENDER_ONLY:
    cards = d[SECTION]
    print(f"=== {SECTION} {len(cards)}장 scrydex 가격 fetch (8 workers) ===", flush=True)
    res = {}
    with ThreadPoolExecutor(max_workers=8) as ex:
        futs = {ex.submit(fetch_one, c): c['ref'] for c in cards}
        done = 0
        for f in as_completed(futs):
            ref, jp = f.result(); res[ref] = jp; done += 1
            if done % 50 == 0:
                print(f"  {done}/{len(cards)}", flush=True)
    n = 0
    for c in cards:
        jp = res.get(c['ref'])
        c['jp_krw'] = jp
        c['ko_est'] = round(jp * FROZEN.get(c['rarity'], GHIT)) if jp else None
        if jp:
            n += 1
    json.dump(d, open(os.path.join(P, 'gaps_enriched.json'), 'w'), ensure_ascii=False)
    print(f"enriched {n}/{len(cards)} in {SECTION}", flush=True)

# ── render ──
DATA_JS = json.dumps(d, ensure_ascii=False)
TPL = r'''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><title>카탈로그 갭 검수 (가격)</title>
<style>
*{box-sizing:border-box;font-family:-apple-system,system-ui,sans-serif}
body{margin:0;background:#f4f5f7;color:#1a1a1a}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid #ddd;padding:10px 16px;z-index:10;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.tabs{display:flex;gap:8px;margin-bottom:8px}
.tab{padding:6px 16px;border-radius:20px;border:1px solid #ccc;background:#fff;cursor:pointer;font-weight:600;font-size:14px}
.tab.on{background:#2962ff;color:#fff;border-color:#2962ff}
.bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap;font-size:13px}
select,input{padding:5px 8px;border:1px solid #ccc;border-radius:6px;font-size:13px}
button{cursor:pointer;border:none;border-radius:6px;padding:6px 12px;font-weight:600;font-size:13px}
.btn-bulk{background:#2962ff;color:#fff}.btn-exp{background:#37474f;color:#fff}
.btn-keep{background:#e8f5e9;color:#2e7d32}.btn-rej{background:#ffebee;color:#c62828}
.stat{margin-left:auto;font-weight:700}
.grid{padding:14px;display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:12px}
.card{background:#fff;border:2px solid #eee;border-radius:10px;padding:10px;display:flex;gap:10px}
.card.KEEP{border-color:#66bb6a;background:#f1f8f2}.card.REJECT{border-color:#ef9a9a;opacity:.5}
.card img{width:90px;height:126px;object-fit:contain;background:#fafafa;border-radius:6px}
.meta{flex:1;min-width:0;font-size:12px;line-height:1.5}
.ko{font-size:15px;font-weight:700}.ko input{width:100%;font-size:14px;font-weight:700;margin-top:2px}
.badge{display:inline-block;padding:1px 7px;border-radius:10px;font-size:11px;font-weight:700;margin-right:4px}
.HIGH{background:#e8f5e9;color:#2e7d32}.MEDIUM{background:#fff8e1;color:#f57f17}.LOW{background:#ffebee;color:#c62828}.rar{background:#ede7f6;color:#5e35b1}
.price{margin-top:4px;font-size:13px}.ko-est{color:#c62828;font-weight:800}.jp-raw{color:#555}
.lnk{color:#1565c0;text-decoration:none;font-size:11px;margin-right:8px}
.acts{margin-top:6px;display:flex;gap:6px}.muted{color:#888}
</style></head><body>
<header><div class="tabs">
 <div class="tab on" data-t="main" onclick="tab('main')">본세트 <span id="cm"></span></div>
 <div class="tab" data-t="promo" onclick="tab('promo')">프로모 <span id="cp"></span></div></div>
<div class="bar">
 <select id="fset" onchange="render()"></select>
 <select id="fstat" onchange="render()"><option value="">전체상태</option><option>PENDING</option><option>KEEP</option><option>REJECT</option></select>
 <select id="fconf" onchange="render()"><option value="">전체신뢰도</option><option>HIGH</option><option>MEDIUM</option><option>LOW</option></select>
 <input type="number" id="fmin" placeholder="최소 예상KO(원)" oninput="render()" style="width:130px">
 <input type="text" id="fq" placeholder="이름검색" oninput="render()" style="width:110px">
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
function vis(){const fs=fset.value,ft=fstat.value,fc=fconf.value,q=fq.value.trim(),mv=parseFloat(fmin.value)||0;
 let r=DATA[cur].filter(c=>(!fs||c.set===fs)&&(!ft||c.status===ft)&&(!fc||c.conf===fc)&&(!q||(c.ko+c.jp).includes(q))&&((c.ko_est||0)>=mv));
 r.sort((a,b)=>(b.ko_est||0)-(a.ko_est||0));return r;}
function won(n){return n?n.toLocaleString()+'원':'—';}
function render(){const v=vis();
 document.getElementById('grid').innerHTML=v.map(c=>`<div class="card ${c.status}"><img src="${c.img}" loading="lazy" onerror="this.style.opacity=.2"><div class="meta">
 <div class="ko">${c.ko?c.ko:`<input placeholder="KO이름 입력" oninput="editKo('${c.ref}',this.value)">`}</div>
 <div class="muted">${c.jp}</div><div><span class="badge rar">${c.rarity}</span><span class="badge ${c.conf}">${c.conf}</span> ${c.sup}</div>
 <div class="price"><span class="ko-est">예상 ${won(c.ko_est)}</span> <span class="jp-raw">· JP ${won(c.jp_krw)}</span></div>
 <div class="muted">${c.set} · ${c.num}</div>
 <div><a class="lnk" href="${c.scrydex}" target="_blank">scrydex↗</a><a class="lnk" href="${c.pc}" target="_blank">pokemoncard검색↗</a></div>
 <div class="acts"><button class="btn-keep" onclick="setStatus('${c.ref}','KEEP')">KEEP</button><button class="btn-rej" onclick="setStatus('${c.ref}','REJECT')">REJECT</button></div>
 </div></div>`).join('');
 const a=DATA[cur];const keepVal=a.filter(c=>c.status==='KEEP').reduce((s,c)=>s+(c.ko_est||0),0);
 document.getElementById('stat').textContent=`보임 ${v.length} | KEEP ${a.filter(c=>c.status==='KEEP').length}(예상합 ${keepVal.toLocaleString()}원) · REJECT ${a.filter(c=>c.status==='REJECT').length} · 대기 ${a.filter(c=>c.status==='PENDING').length}`;
 document.getElementById('cm').textContent=DATA.main.length;document.getElementById('cp').textContent=DATA.promo.length;}
function exp(){const out=[];for(const k of ['main','promo'])DATA[k].forEach(c=>{if(c.status==='KEEP')out.push({ref:c.ref,set:c.set,num:c.num,ko:c.ko,jp:c.jp,rarity:c.rarity,sup:c.sup,promo:c.promo,jp_krw:c.jp_krw,ko_est:c.ko_est});});
 const b=new Blob([JSON.stringify(out,null,2)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='approved_'+new Date().toISOString().slice(0,10)+'.json';a.click();alert('KEEP '+out.length+'장 내보냄');}
buildSets();render();
</script></body></html>'''
open(os.path.join(P, 'review_priced.html'), 'w').write(TPL.replace('__DATA__', DATA_JS))
print("→ review_priced.html 렌더 완료", flush=True)
