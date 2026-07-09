"""gap 후보 ⇄ prod cards 매핑 역조회 → KO/JP/EN 3장 비교 + 중복 판정 검수 HTML.

판정 (prod_cards_snapshot 기준):
  candidate_jp_ref ∈ prod.jp_scrydex_ref  → EXCLUDE_ALREADY_MAPPED_JP
  candidate_en_ref ∈ prod.en_scrydex_ref  → EXCLUDE_ALREADY_MAPPED_EN
  둘 다 아님                                → ADD

카드 한 장 = [KO 공식][JP 후보][EN 후보][기존 prod 매핑] 4슬롯 가로 비교.
 - KO 이미지: 데이터에 KO 공식 per-card 이미지 없음 → 정발 아트=JP 동일이라 scrydex 아트 사용("정발" 라벨).
 - JP 이미지: candidate_jp_ref scrydex
 - EN 이미지: candidate_en_ref scrydex (c['en_ref'] 없으면 "EN 미해결")
 - 기존 prod: EXCLUDE일 때 매핑된 prod 카드 식별정보 + scrydex 이미지

prod 는 read-only COPY 덤프 기준.  실행: python dedup_render.py
"""
import json, csv, collections, os

P = os.path.dirname(os.path.abspath(__file__))
SCRY_IMG = "https://images.scrydex.com/pokemon/{}/medium"


def norm(x):
    return (x or '').strip()


def is_real(ref):
    return bool(ref) and not ref.startswith('NO_')


def scry_img(ref):
    ref = norm(ref)
    return SCRY_IMG.format(ref) if is_real(ref) else ''


# ── prod snapshot ──
jpmap = collections.defaultdict(list)
enmap = collections.defaultdict(list)
prod_n = 0
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        prod_n += 1
        jr, er = norm(r['jp_scrydex_ref']), norm(r['en_scrydex_ref'])
        if is_real(jr):
            jpmap[jr].append(r)
        if is_real(er):
            enmap[er].append(r)

prod_prod = {}
pp = os.path.join(P, 'prod_products_snapshot.csv')
if os.path.exists(pp):
    with open(pp) as f:
        for r in csv.DictReader(f):
            prod_prod[r['product_id']] = r

gaps = json.load(open(os.path.join(P, 'gaps_enriched.json')))


def existing_box(ex):
    prod = prod_prod.get(ex['product_id'], {})
    # 기존 카드 이미지: en ref 우선(있으면) 없으면 jp ref
    img = scry_img(ex['en_scrydex_ref']) or scry_img(ex['jp_scrydex_ref'])
    return {
        'card_id': ex['card_id'], 'name': ex['name'], 'product_id': ex['product_id'],
        'product_name': prod.get('name', ''), 'num': ex['collection_number'],
        'rarity': ex['rarity_code'], 'jp_ref': ex['jp_scrydex_ref'],
        'en_ref': ex['en_scrydex_ref'], 'img': img,
    }


def judge(c):
    jp = norm(c.get('ref'))
    en = norm(c.get('en_ref'))
    if is_real(jp) and jp in jpmap:
        return 'EXCLUDE_JP', existing_box(jpmap[jp][0]), en
    if is_real(en) and en in enmap:
        return 'EXCLUDE_EN', existing_box(enmap[en][0]), en
    return 'ADD', None, en


out = {'main': [], 'promo': []}
stat = {}
for sect in ['main', 'promo']:
    cnt = collections.Counter()
    for c in gaps.get(sect, []):
        verdict, ex, en = judge(c)
        cnt[verdict] += 1
        out[sect].append({
            'ref': c.get('ref'), 'en_ref': en,
            'ko': c.get('ko') or '', 'jp': c.get('jp') or '',
            'en_name': c.get('en_name') or '',          # EN enrich 패스 후 채워짐
            'set': c.get('set') or '', 'num': c.get('num') or '',
            'en_set': c.get('en_set') or '', 'en_num': c.get('en_num') or '',
            'rarity': c.get('rarity') or '', 'conf': c.get('conf') or '',
            'ko_img': c.get('img') or '',                # 정발 아트=scrydex JP
            'jp_img': scry_img(c.get('ref')),
            'en_img': scry_img(en),
            'scrydex': c.get('scrydex') or '', 'pc': c.get('pc') or '',
            'jp_krw': c.get('jp_krw'), 'ko_est': c.get('ko_est'),
            'verdict': verdict, 'ex': ex,
        })
    stat[sect] = dict(cnt)

print('prod snapshot cards:', prod_n, '| jp distinct', len(jpmap), '| en distinct', len(enmap))
for s in ['main', 'promo']:
    print(f'  {s}: {stat[s]}')

DATA = json.dumps(out, ensure_ascii=False)
TPL = r'''<!DOCTYPE html><html lang="ko"><head><meta charset="utf-8"><title>gap 후보 KO/JP/EN 검수 + 중복 판정</title>
<style>
*{box-sizing:border-box;font-family:-apple-system,system-ui,sans-serif}
body{margin:0;background:#f4f5f7;color:#1a1a1a;font-size:13px}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid #ddd;padding:10px 16px;z-index:10;box-shadow:0 1px 4px rgba(0,0,0,.06)}
.tabs{display:flex;gap:8px;margin-bottom:8px}
.tab{padding:6px 16px;border-radius:20px;border:1px solid #ccc;background:#fff;cursor:pointer;font-weight:600}
.tab.on{background:#2962ff;color:#fff;border-color:#2962ff}
.bar{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
select,input{padding:5px 8px;border:1px solid #ccc;border-radius:6px;font-size:13px}
.seg{display:inline-flex;border:1px solid #ccc;border-radius:6px;overflow:hidden}
.seg button{border:none;background:#fff;padding:5px 12px;cursor:pointer;font-weight:600}
.seg button.on{background:#37474f;color:#fff}
.stat{margin-left:auto;font-weight:700}
.grid{padding:14px;display:grid;grid-template-columns:1fr;gap:12px;max-width:1200px;margin:0 auto}
.card{background:#fff;border:2px solid #eee;border-radius:12px;padding:12px}
.card.ADD{border-color:#66bb6a}.card.EXCLUDE_JP,.card.EXCLUDE_EN{border-color:#ef9a9a;background:#fff7f6}
.hd{display:flex;align-items:center;gap:8px;margin-bottom:8px}
.hd .nm{font-size:16px;font-weight:800}
.cols{display:flex;gap:10px;flex-wrap:wrap}
.col{flex:1;min-width:200px;border:1px solid #eee;border-radius:8px;padding:8px;background:#fafbfc}
.col.ko{background:#f1f6ff}.col.jp{background:#fff8f1}.col.en{background:#f3fbf3}.col.ex{background:#fbe9e7;border-color:#ef9a9a}
.col .lbl{font-size:11px;font-weight:800;letter-spacing:.04em;color:#555;margin-bottom:5px}
.col img{width:100%;max-width:150px;height:200px;object-fit:contain;background:#fff;border-radius:6px;display:block;margin:0 auto 6px}
.unres{height:200px;display:flex;align-items:center;justify-content:center;background:#fff;border:1px dashed #f0a;border-radius:6px;color:#c2185b;font-weight:700;margin-bottom:6px}
.id{font-size:12px;line-height:1.55}
.refs{font-family:ui-monospace,Menlo,monospace;font-size:11px;color:#1565c0;word-break:break-all}
.badge{display:inline-block;padding:1px 8px;border-radius:10px;font-size:11px;font-weight:800}
.v-ADD{background:#e8f5e9;color:#2e7d32}.v-EXCLUDE_JP{background:#ffebee;color:#c62828}.v-EXCLUDE_EN{background:#fff3e0;color:#e65100}
.rar{background:#ede7f6;color:#5e35b1}.HIGH{background:#e8f5e9;color:#2e7d32}.MEDIUM{background:#fff8e1;color:#f57f17}.LOW{background:#ffebee;color:#c62828}
.muted{color:#888}.lnk{color:#1565c0;text-decoration:none}.ko-est{color:#c62828;font-weight:800}
.warn{font-size:11px;color:#c2185b}
</style></head><body>
<header><div class="tabs">
 <div class="tab on" data-t="main" onclick="tab('main')">본세트 <span id="cm"></span></div>
 <div class="tab" data-t="promo" onclick="tab('promo')">프로모 <span id="cp"></span></div></div>
<div class="bar">
 <div class="seg"><button class="on" data-v="" onclick="seg('')">전체</button>
  <button data-v="ADD" onclick="seg('ADD')">ADD</button>
  <button data-v="EXCLUDE" onclick="seg('EXCLUDE')">EXCLUDE</button></div>
 <select id="fset" onchange="render()"></select>
 <input type="text" id="fq" placeholder="이름검색" oninput="render()" style="width:130px">
 <span class="stat" id="stat"></span></div></header>
<div class="grid" id="grid"></div>
<script>
const DATA=__DATA__;let cur='main',segv='';
const esc=s=>(s==null?'':(''+s)).replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));
const won=n=>n?n.toLocaleString()+'원':'—';
const imgEl=(u,oe)=>u?`<img src="${esc(u)}" loading="lazy" onerror="this.replaceWith(Object.assign(document.createElement('div'),{className:'unres',textContent:'이미지 없음'}))">`:`<div class="unres">${oe||'없음'}</div>`;
function tab(t){cur=t;document.querySelectorAll('.tab').forEach(e=>e.classList.toggle('on',e.dataset.t===t));buildSets();render();}
function seg(v){segv=v;document.querySelectorAll('.seg button').forEach(e=>e.classList.toggle('on',e.dataset.v===v));render();}
function buildSets(){const s=[...new Set(DATA[cur].map(c=>c.set))].sort();fset.innerHTML='<option value="">전체세트('+DATA[cur].length+')</option>'+s.map(x=>'<option>'+esc(x)+'</option>').join('');}
function vis(){const fs=fset.value,q=fq.value.trim();
 return DATA[cur].filter(c=>(!fs||c.set===fs)&&(!q||((c.ko+c.jp+(c.en_name||'')).includes(q)))&&(!segv||(segv==='EXCLUDE'?c.verdict.startsWith('EXCLUDE'):c.verdict===segv)));}
function cardHtml(c){
 const ko=`<div class="col ko"><div class="lbl">KO 공식 <span class="muted">(정발 아트=JP)</span></div>
   ${imgEl(c.ko_img)}<div class="id"><b>${esc(c.ko||'?')}</b><br>${esc(c.set)}<br>번호 ${esc(c.num)} · <span class="badge rar">${esc(c.rarity)}</span><br><a class="lnk" href="${esc(c.pc)}" target="_blank">pokemoncard 검색↗</a></div></div>`;
 const jp=`<div class="col jp"><div class="lbl">JP 후보</div>
   ${imgEl(c.jp_img)}<div class="id"><b>${esc(c.jp)}</b><br><span class="refs">${esc(c.ref)}</span><br>번호 ${esc(c.num)}<br><a class="lnk" href="${esc(c.scrydex)}" target="_blank">scrydex↗</a></div></div>`;
 const en=`<div class="col en"><div class="lbl">EN 후보</div>
   ${c.en_ref?imgEl(c.en_img):`<div class="unres">EN 미해결</div>`}
   <div class="id">${c.en_ref?`<b>${esc(c.en_name||'')}</b><br><span class="refs">${esc(c.en_ref)}</span><br>${esc(c.en_set)} ${esc(c.en_num)}`:`<span class="warn">EN ref 미해결<br>(scrydex 2단 매칭 대기)</span>`}</div></div>`;
 let ex='';
 if(c.ex){const e=c.ex;ex=`<div class="col ex"><div class="lbl">↳ 기존 prod 매핑 (추가 제외)</div>
   ${imgEl(e.img)}<div class="id"><b>${esc(e.name)}</b> <span class="muted">${esc(e.card_id)}</span><br>${esc(e.product_name||e.product_id)}<br>번호 ${esc(e.num)} · <span class="badge rar">${esc(e.rarity)}</span><br>
   <span class="refs">JP ${esc(e.jp_ref)}<br>EN ${esc(e.en_ref||'—')}</span></div></div>`;}
 return `<div class="card ${c.verdict}">
   <div class="hd"><span class="nm">${esc(c.ko||c.jp||'?')}</span><span class="badge v-${c.verdict}">${c.verdict}</span>
     <span class="badge ${esc(c.conf)}">${esc(c.conf)}</span><span class="muted ko-est">예상 ${won(c.ko_est)}</span><span class="muted">· JP ${won(c.jp_krw)}</span></div>
   <div class="cols">${ko}${jp}${en}${ex}</div></div>`;}
function render(){const v=vis();
 grid.innerHTML=v.map(cardHtml).join('');
 const a=DATA[cur],add=a.filter(c=>c.verdict==='ADD').length,ej=a.filter(c=>c.verdict==='EXCLUDE_JP').length,ee=a.filter(c=>c.verdict==='EXCLUDE_EN').length;
 stat.textContent=`보임 ${v.length} | ADD ${add} · EXCLUDE_JP ${ej} · EXCLUDE_EN ${ee} (총 ${a.length})`;
 cm.textContent=DATA.main.length;cp.textContent=DATA.promo.length;}
buildSets();render();
</script></body></html>'''
open(os.path.join(P, 'dedup_review.html'), 'w').write(TPL.replace('__DATA__', DATA))
print('→ dedup_review.html 렌더 완료 (KO/JP/EN 4슬롯 비교)')
