#!/usr/bin/env python3
"""UNRESOLVED 42 jp_ref 해결 (read-only).
조건: 시리즈 JP세트 + 카드명(jp_candidates) + 레어도 + JP이미지 200 + KO↔JP 시각일치(DINOv2) + 후보 유일.
하나라도 애매하면 UNRESOLVED 유지. prod write 0.
"""
import json, urllib.request, urllib.parse, os, re
import numpy as np, cv2, torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel

BASE = '/Users/fury/pokemon-card-app/scanner'
UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"
DEV = 'mps' if torch.backends.mps.is_available() else 'cpu'
print(f"모델 로드 ({DEV})...")
proc = AutoImageProcessor.from_pretrained('facebook/dinov2-base')
model = AutoModel.from_pretrained(f'{BASE}/model/dinov2_finetuned').to(DEV).eval()

def to_bgr(data):
    arr = np.frombuffer(data, np.uint8)
    img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
    if img is None:
        pil = Image.open(__import__('io').BytesIO(data)).convert('RGB')
        img = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
    return img

def embed(bgr):
    img = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
    inp = proc(images=img, return_tensors='pt').to(DEV)
    with torch.no_grad():
        out = model(**inp)
    cls = out.last_hidden_state[:, 0, :]
    pm = out.last_hidden_state[:, 1:, :].mean(dim=1)
    e = torch.cat([cls, pm], -1).cpu().numpy()[0]
    return (e / (np.linalg.norm(e) + 1e-8)).astype(np.float32)

_cache = {}
def fetch_embed(url):
    if url in _cache: return _cache[url]
    try:
        d = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': UA}), timeout=20).read()
        if len(d) < 3000: _cache[url] = None; return None
        e = embed(to_bgr(d)); _cache[url] = e; return e
    except Exception:
        _cache[url] = None; return None

def scrydex_rarity(ref):
    try:
        h = urllib.request.urlopen(urllib.request.Request(f"https://scrydex.com/pokemon/cards/_/{ref}", headers={'User-Agent': UA}), timeout=15).read().decode('utf-8', 'ignore')
        if len(h) < 5000: return None
        rs = re.findall(r'>(Double Rare|Art Rare|Super Rare|Special Art Rare|Special Illustration Rare|Ultra Rare|Hyper Rare|Mega Ultra Rare|Illustration Rare)<', h)
        return rs[0] if rs else 'OK'
    except Exception:
        return None

RMAP = {'Double Rare': 'RR', 'Art Rare': 'AR', 'Super Rare': 'SR', 'Special Art Rare': 'SAR',
        'Special Illustration Rare': 'SAR', 'Ultra Rare': 'UR', 'Hyper Rare': 'HR', 'Mega Ultra Rare': 'MUR'}

jm = {c['code']: c for c in json.load(open('jp_match_preview.json'))}
res = {r['code']: r for r in json.load(open('/tmp/img_dedup_results.json'))}
unres = [jm[code] for code, r in res.items() if r['score'] < 0.75 and not jm[code].get('jp_ref')]
print(f"UNRESOLVED {len(unres)}장 해결 시도\n")

out = []
for i, c in enumerate(unres):
    ko_e = fetch_embed(c.get('ko_image_url', ''))
    cand_refs = []
    for jc in (c.get('jp_candidates') or []):
        cand_refs.append(jc['ref'])
    sjs = c.get('series_jp_set')
    if sjs:
        try: cand_refs.append(f"{sjs}-{int(c['ko_collection_no'])}")
        except Exception: pass
    cand_refs = list(dict.fromkeys(cand_refs))
    sims = []
    if ko_e is not None:
        for ref in cand_refs:
            je = fetch_embed(f"https://images.scrydex.com/pokemon/{ref}/medium")
            if je is not None:
                sims.append((ref, float(np.dot(ko_e, je))))
    sims.sort(key=lambda x: -x[1])
    verdict, chosen, reason = 'UNRESOLVED', '', ''
    if sims:
        top_ref, top_s = sims[0]
        second_s = sims[1][1] if len(sims) > 1 else 0.0
        uniq = (top_s >= 0.85) and (len(sims) == 1 or (top_s - second_s) >= 0.05)
        rar_ok = True
        if uniq:
            sr = scrydex_rarity(top_ref)
            if sr and sr in RMAP:
                rar_ok = (RMAP[sr] == c['ko_rarity'])
            if rar_ok:
                verdict, chosen = 'RESOLVED', top_ref
                reason = f"vis={top_s:.3f} 2nd={second_s:.3f} rar={sr}"
            else:
                reason = f"rarity불일치 {sr}!={c['ko_rarity']} vis={top_s:.3f}"
        else:
            reason = f"애매 top={top_s:.3f} 2nd={second_s:.3f} n={len(sims)}"
    else:
        reason = 'KO/후보 이미지 없음'
    out.append({'code': c['code'], 'ko_name': c['ko_name'], 'rarity': c['ko_rarity'],
                'ko_no': c['ko_collection_no'], 'series_jp_set': sjs,
                'verdict': verdict, 'resolved_ref': chosen, 'reason': reason,
                'sims': [(r, round(s, 3)) for r, s in sims[:3]]})
    print(f"  [{i+1}/{len(unres)}] {c['ko_name']}({c['ko_rarity']}) → {verdict} {chosen} | {reason}")

json.dump(out, open('/tmp/resolve_results.json', 'w'), ensure_ascii=False, indent=1)
R = sum(1 for o in out if o['verdict'] == 'RESOLVED')
print(f"\n=== RESOLVED {R} · UNRESOLVED {len(out)-R} ===")
