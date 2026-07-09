#!/usr/bin/env python3
"""KO/JP/EN 3언어 교차 시각 유사도 (DINOv2). read-only. v6 검수증거용."""
import json, urllib.request, os
import numpy as np, cv2, torch, io
from PIL import Image
from transformers import AutoImageProcessor, AutoModel

BASE = '/Users/fury/pokemon-card-app/scanner'
UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"
DEV = 'mps' if torch.backends.mps.is_available() else 'cpu'
print(f"모델 로드 ({DEV})...")
proc = AutoImageProcessor.from_pretrained('facebook/dinov2-base')
model = AutoModel.from_pretrained(f'{BASE}/model/dinov2_finetuned').to(DEV).eval()

def embed_bgr(bgr):
    img = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
    inp = proc(images=img, return_tensors='pt').to(DEV)
    with torch.no_grad():
        out = model(**inp)
    e = torch.cat([out.last_hidden_state[:, 0, :], out.last_hidden_state[:, 1:, :].mean(1)], -1).cpu().numpy()[0]
    return (e / (np.linalg.norm(e) + 1e-8)).astype(np.float32)

_c = {}
def emb_url(url):
    if not url: return None
    if url in _c: return _c[url]
    try:
        d = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=20).read()
        if len(d) < 2500: _c[url] = None; return None
        arr = np.frombuffer(d, np.uint8); bgr = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if bgr is None:
            bgr = cv2.cvtColor(np.array(Image.open(io.BytesIO(d)).convert('RGB')), cv2.COLOR_RGB2BGR)
        e = embed_bgr(bgr); _c[url] = e; return e
    except Exception:
        _c[url] = None; return None

def emb_path(p):
    if not os.path.exists(p): return None
    bgr = cv2.imread(p)
    return embed_bgr(bgr) if bgr is not None else None

def scry(ref): return f"https://images.scrydex.com/pokemon/{ref}/medium" if ref else ''

jm = {c['code']: c for c in json.load(open('jp_match_preview.json'))}
rf = json.load(open('/tmp/resolve_final.json'))
resolved_ref = {o['code']: o['resolved_ref'] for o in rf['resolved']}
HI = {'RR','RRR','AR','SR','SAR','SSR','UR','HR','CSR','MUR','MA','CHR'}
scope = [c for c in jm.values() if c.get('verdict') != 'EXCLUDE_JP' and c['ko_rarity'] in HI
         and (('포켓몬' in c['type']) or ('서포트' in c['type']))]
print(f"대상 {len(scope)}장")

out = {}
for i, c in enumerate(scope):
    code = c['code']
    ko_e = emb_path(f"/tmp/cand_imgs/{code}.png")
    if ko_e is None: ko_e = emb_url(c.get('ko_image_url', ''))
    jp_ref = c.get('jp_ref') or resolved_ref.get(code, '')
    en_ref = c.get('en_ref') or ''
    jp_url = c.get('jp_image_url') or scry(jp_ref)
    en_url = c.get('en_image_url') or scry(en_ref)
    jp_e = emb_url(jp_url); en_e = emb_url(en_url) if en_ref else None
    def cos(a, b): return round(float(np.dot(a, b)), 3) if (a is not None and b is not None) else None
    out[code] = {'jp_url': jp_url, 'en_url': en_url if en_ref else '',
                 'ko_jp': cos(ko_e, jp_e), 'ko_en': cos(ko_e, en_e), 'jp_en': cos(jp_e, en_e),
                 'en_loaded': en_e is not None, 'has_en_ref': bool(en_ref)}
    if (i + 1) % 40 == 0: print(f"  ...{i+1}/{len(scope)}")

json.dump(out, open('/tmp/crosslang_sims.json', 'w'), ensure_ascii=False)
ne = sum(1 for v in out.values() if v['has_en_ref'])
nel = sum(1 for v in out.values() if v['has_en_ref'] and v['en_loaded'])
print(f"\n완료. en_ref 보유 {ne} · EN이미지 로드성공 {nel}")
print(f"  KO↔JP sim 분포: " + str({k: sum(1 for v in out.values() if v['ko_jp'] is not None and lo <= v['ko_jp'] < hi) for k, (lo, hi) in {'≥0.9': (0.9, 2), '0.8-0.9': (0.8, 0.9), '<0.8': (-2, 0.8)}.items()}))
