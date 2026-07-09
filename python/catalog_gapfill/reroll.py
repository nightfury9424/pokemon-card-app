"""리롤 엔진 (비파괴) — reroll_request.json 입력 → 새 EN 후보만 탐색 → reroll_result.json + reroll_review.html.
 ★jp_match_preview.json(현재 검수본)은 읽기전용. 절대 수정/덮어쓰기 안 함.
 새 후보 채택은 reroll_review.html 에서 사람이 고른 뒤 별도 merge 단계에서만 반영.
   python reroll.py reroll_request_YYYYMMDD.json
 scanner_v2 env (DINOv2 시각 재판별). write/POST/insert 0.
"""
import json, re, os, sys, collections, urllib.request, html, numpy as np, cv2, torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel
from concurrent.futures import ThreadPoolExecutor

P = os.path.dirname(os.path.abspath(__file__))
UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"
BASE_MODEL = "facebook/dinov2-base"
FT = "/Users/fury/pokemon-card-app/scanner/model/dinov2_finetuned"
MODEL_NAME = FT if os.path.exists(FT) else BASE_MODEL
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"
TOP_MIN = float(os.environ.get("TOP_MIN", "0.42"))
MARGIN = float(os.environ.get("MARGIN", "0.05"))
PROMO = ['svp', 'swshp', 'mep']
SCRY = "https://images.scrydex.com/pokemon/{}/medium"

if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
    print("사용법: python reroll.py <reroll_request_*.json>  (HTML '리롤요청 내보내기' 산출물)")
    print("※ 비파괴 — jp_match_preview.json 은 건드리지 않음. 새 후보만 reroll_result.json/reroll_review.html 로.")
    sys.exit(1)
REQ = json.load(open(sys.argv[1]))

proc = AutoImageProcessor.from_pretrained(BASE_MODEL)
model = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE).eval()
print(f"model={MODEL_NAME} device={DEVICE} | 리롤요청 {len(REQ)}장", flush=True)


def get(u):
    try:
        return urllib.request.urlopen(urllib.request.Request(u, headers={"User-Agent": UA}), timeout=25).read().decode('utf-8', 'ignore')
    except Exception:
        return ''


def nname(s):
    return re.sub(r'[^a-z0-9]', '', (s or '').lower())


def jp_en_name(ref):
    h = get(f"https://scrydex.com/pokemon/cards/_/{ref}")
    m = re.search(r'<title>([^<|]+)', h)
    return re.sub(r'\s*#\d.*$', '', html.unescape(m.group(1))).strip() if m else ''


_bc = {}


def fetch_bgr(url):
    if url in _bc:
        return _bc[url]
    try:
        b = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=20).read()
        _bc[url] = cv2.imdecode(np.frombuffer(b, np.uint8), cv2.IMREAD_COLOR)
    except Exception:
        _bc[url] = None
    return _bc[url]


def emb(bgr):
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    inp = proc(images=Image.fromarray(rgb), return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        out = model(**inp)
    e = torch.cat([out.last_hidden_state[:, 0, :], out.last_hidden_state[:, 1:, :].mean(dim=1)], dim=-1).cpu().numpy()[0]
    return (e / (np.linalg.norm(e) + 1e-8)).astype(np.float32)


# 현재 검수본 (읽기전용)
cur = {r['code']: r for r in json.load(open(os.path.join(P, 'jp_match_preview.json')))}
mh = get("https://scrydex.com/pokemon/expansions")
setcode_slug = {}
for slug, sc in re.findall(r'/pokemon/expansions/([a-z0-9-]+)/([a-z0-9]+)"', mh):
    setcode_slug.setdefault(sc, slug)


def sets_for(c):
    s = []
    if c.get('series_en_set'):
        s.append(c['series_en_set'])
    for sc, _ in re.findall(r'([a-z0-9]+):(\d+)', c.get('series_en_dist') or ''):
        s.append(sc)
    return list(dict.fromkeys(s + PROMO))


need = set()
for it in REQ:
    c = cur.get(it['code'])
    if c:
        need |= set(sets_for(c))


def fetch_set(en):
    slug = setcode_slug.get(en)
    if not slug:
        return en, {}
    h = get(f"https://scrydex.com/pokemon/expansions/{slug}/{en}")
    idx = collections.defaultdict(set)
    for s, ref in re.findall(r'/cards/([a-z0-9-]+)/(' + re.escape(en) + r'-\d+[a-z]*)\?variant', h):
        idx[nname(s)].add(ref)
    return en, {k: sorted(v) for k, v in idx.items()}


print(f"세트 인덱싱 {len(need)}…", flush=True)
enidx = {}
with ThreadPoolExecutor(max_workers=6) as ex:
    for en, idx in ex.map(fetch_set, need):
        enidx[en] = idx

result = []
for it in REQ:
    c = cur.get(it['code'])
    if not c:
        continue
    rejected = it.get('rejected_or_bad_candidate') or it.get('current_en_ref')
    jpen = jp_en_name(c['jp_ref']) if c.get('jp_ref') else ''
    found = []
    for s in sets_for(c):
        found += enidx.get(s, {}).get(nname(jpen), [])
    found = [x for x in dict.fromkeys(found) if x != rejected]
    src = fetch_bgr(c.get('jp_image_url') or '')
    scored = []
    if src is not None and found:
        se = emb(src)
        scored = sorted(((x, round(float(np.dot(se, emb(b))), 4)) for x in found for b in [fetch_bgr(SCRY.format(x))] if b is not None), key=lambda z: -z[1])
    top = scored[0] if scored else (None, -1)
    second = scored[1] if len(scored) > 1 else (None, -1)
    sug = top[0] if (top[0] and top[1] >= TOP_MIN and top[1] - second[1] >= MARGIN) else None
    result.append({
        'code': c['code'], 'ko_name': c['ko_name'], 'ko_rarity': c['ko_rarity'],
        'productId': c.get('series_productId'), 'ko_image_url': c['ko_image_url'], 'jp_image_url': c.get('jp_image_url'),
        'current_jp_ref': c.get('jp_ref'), 'current_en_ref': it.get('current_en_ref'),
        'current_en_candidates': it.get('current_en_candidates') or c.get('en_candidates') or [],
        'rejected': rejected, 'jp_en_name': jpen,
        'new_candidates': [{'ref': r, 'score': v} for r, v in scored],
        'suggested_new_en_ref': sug, 'suggested_score': top[1] if sug else None,
        'reason': (f"리롤 시각최고 {top[0]} ({top[1]})" if sug else f"새 후보 {len(scored)}개·확신부족 → 사람선택"),
    })
    print(f"  {c['ko_name'][:12]:12}[{c['ko_rarity']:3}] 새후보 " + (' '.join(f'{r}:{v}' for r, v in scored[:4]) or '없음'), flush=True)

json.dump(result, open(os.path.join(P, 'reroll_result.json'), 'w'), ensure_ascii=False, indent=1)

# reroll_review.html — 현재 vs 새 후보, 사람이 채택 → reroll_selection 별도 export
DATA = json.dumps(result, ensure_ascii=False)
TPL = r'''<!DOCTYPE html><html lang=ko><head><meta charset=utf-8><title>리롤 결과 검수 (현재 vs 새 후보)</title><style>
*{box-sizing:border-box;font-family:-apple-system,system-ui,sans-serif}body{margin:0;background:#f4f5f7;font-size:13px}
header{position:sticky;top:0;background:#fff;border-bottom:1px solid #ddd;padding:10px 16px;display:flex;gap:10px;align-items:center}
.tbtn{padding:6px 12px;border:none;border-radius:6px;cursor:pointer;font-weight:700;background:#2e7d32;color:#fff}
.grid{padding:14px;display:grid;gap:12px;max-width:1100px;margin:0 auto}
.card{background:#fff;border:2px solid #e0e0e0;border-radius:12px;padding:12px}
.row{display:flex;gap:12px;flex-wrap:wrap;align-items:flex-start}
.box{border:1px solid #eee;border-radius:8px;padding:8px;text-align:center}.box.cur{background:#fff8f1}.box.new{background:#f3fbf3;flex:1}
img{height:150px;object-fit:contain;background:#fff;border-radius:5px}.refs{font-family:ui-monospace,Menlo;font-size:11px;color:#1565c0}
.cand{display:inline-block;margin:3px;cursor:pointer;border:2px solid #ccc;border-radius:6px;padding:3px}.cand.pick{border-color:#2e7d32;box-shadow:0 0 0 2px #66bb6a}
.cand img{height:120px}.sug{color:#2e7d32;font-weight:800}.muted{color:#888}.nm{font-size:15px;font-weight:800;margin-bottom:6px}
</style></head><body>
<header><b>리롤 결과 검수</b> — 현재 후보 보존, 새 후보 중 맞는 것 클릭 → 채택 내보내기 (merge는 별도)
<button class=tbtn onclick=exp()>리롤 채택 내보내기</button><span id=st style=margin-left:auto;font-weight:700></span></header>
<div class=grid id=grid></div><script>
const DATA=__DATA__;const PK=JSON.parse(localStorage.getItem('reroll_pick')||'{}');
const esc=s=>(s==null?'':(''+s)).replace(/[&<>"]/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[m]));
const I=r=>`https://images.scrydex.com/pokemon/${r}/medium`;
function pick(code,ref){PK[code]=(PK[code]==ref?null:ref);if(!PK[code])delete PK[code];localStorage.setItem('reroll_pick',JSON.stringify(PK));render();}
function exp(){const o=Object.entries(PK).map(([code,en])=>({code,en_ref:en}));if(!o.length){alert('채택 없음');return;}
 const b=new Blob([JSON.stringify(o,null,1)],{type:'application/json'});const a=document.createElement('a');a.href=URL.createObjectURL(b);a.download='reroll_selection_'+new Date().toISOString().slice(0,10)+'.json';a.click();alert('채택 '+o.length+'건 — merge 단계로');}
function render(){grid.innerHTML=DATA.map(c=>`<div class=card><div class=nm>${esc(c.ko_name)} <span class=muted>[${esc(c.ko_rarity)}] ${esc(c.code)} · ${esc(c.jp_en_name)}</span></div><div class=row>
 <div class=box><div class=muted>KO 공식</div><img src="${esc(c.ko_image_url)}"></div>
 <div class=box><div class=muted>JP (source)</div><img src="${esc(c.jp_image_url)}"><div class=refs>${esc(c.current_jp_ref)}</div></div>
 <div class="box cur"><div class=muted>현재 EN(보존)</div>${c.current_en_ref?`<img src="${esc(I(c.current_en_ref))}"><div class=refs>${esc(c.current_en_ref)}</div>`:'<div class=muted style=height:150px>현재 없음</div>'}</div>
 <div class="box new"><div class=muted>새 후보 — 맞는 것 클릭 ${c.suggested_new_en_ref?`(추천 <span class=sug>${esc(c.suggested_new_en_ref)}</span>)`:''}</div>
   ${c.new_candidates.length?c.new_candidates.map(n=>`<div class="cand ${PK[c.code]==n.ref?'pick':''}" onclick="pick('${c.code}','${esc(n.ref)}')"><img src="${esc(I(n.ref))}"><div class=refs>${esc(n.ref)}<br>${n.score}</div></div>`).join(''):'<span class=muted>새 후보 없음</span>'}</div>
 </div><div class=muted style=margin-top:6px>${esc(c.reason)}</div></div>`).join('');
 st.textContent='채택 '+Object.keys(PK).length+' / '+DATA.length;}
render();</script></body></html>'''
open(os.path.join(P, 'reroll_review.html'), 'w').write(TPL.replace('__DATA__', DATA))
print(f"\n→ reroll_result.json + reroll_review.html ({len(result)}장). jp_match_preview.json 미변경(비파괴).")
