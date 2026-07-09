"""EN 변종 AMBIGUOUS → 스캐너 DINOv2 임베딩(train_agent.get_embedding 동일)으로 시각 자동선택.
 source = JP scrydex 이미지(매칭된 AR/SR 일러스트), candidates = en_candidates 이미지.
 코사인 최고후보가 TOP_MIN 이상 & (1등-2등) MARGIN 이상이면 EN_MATCH_VISUAL 자동승격, 아니면 AMBIGUOUS 유지.
 scanner_v2 env 로 실행. write/POST 0 (jp_match_preview.json 만 갱신).
"""
import json, os, sys, urllib.request, numpy as np, cv2, torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel

P = os.path.dirname(os.path.abspath(__file__))
BASE_MODEL = "facebook/dinov2-base"
FT = "/Users/fury/pokemon-card-app/scanner/model/dinov2_finetuned"
MODEL_NAME = FT if os.path.exists(FT) else BASE_MODEL
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"
TOP_MIN = float(os.environ.get("TOP_MIN", "0.42"))
MARGIN = float(os.environ.get("MARGIN", "0.05"))
UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"

print(f"model={MODEL_NAME} device={DEVICE} TOP_MIN={TOP_MIN} MARGIN={MARGIN}", flush=True)
proc = AutoImageProcessor.from_pretrained(BASE_MODEL)
model = AutoModel.from_pretrained(MODEL_NAME).to(DEVICE).eval()

_cache = {}


def fetch_bgr(url):
    if url in _cache:
        return _cache[url]
    try:
        b = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=20).read()
        arr = cv2.imdecode(np.frombuffer(b, np.uint8), cv2.IMREAD_COLOR)
        _cache[url] = arr
        return arr
    except Exception:
        _cache[url] = None
        return None


def emb(bgr):
    rgb = cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)
    inp = proc(images=Image.fromarray(rgb), return_tensors="pt").to(DEVICE)
    with torch.no_grad():
        out = model(**inp)
    cls = out.last_hidden_state[:, 0, :]
    pm = out.last_hidden_state[:, 1:, :].mean(dim=1)
    e = torch.cat([cls, pm], dim=-1).cpu().numpy()[0]
    return (e / (np.linalg.norm(e) + 1e-8)).astype(np.float32)


SCRY = "https://images.scrydex.com/pokemon/{}/medium"
data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
targets = [r for r in data if r.get('en_conf') == 'EN_MATCH_AMBIGUOUS' and r.get('en_candidates')]
print(f"변종 AMBIGUOUS 대상 {len(targets)}", flush=True)

auto = keep = 0
rows = []
for i, r in enumerate(targets):
    src = fetch_bgr(r.get('jp_image_url') or '')
    if src is None:
        r['en_reason'] = (r.get('en_reason', '') + ' | source 이미지 실패'); keep += 1; continue
    se = emb(src)
    scored = []
    for ref in r['en_candidates']:
        c = fetch_bgr(SCRY.format(ref))
        scored.append((ref, float(np.dot(se, emb(c))) if c is not None else -1.0))
    scored.sort(key=lambda x: -x[1])
    top, second = scored[0], (scored[1] if len(scored) > 1 else (None, -1.0))
    rows.append((r['ko_name'], r['ko_rarity'], r['jp_ref'], scored))
    if top[1] >= TOP_MIN and (top[1] - second[1]) >= MARGIN:
        r['en_ref'] = top[0]; r['en_name'] = r.get('en_name') or ''
        r['en_image_url'] = SCRY.format(top[0]); r['en_conf'] = 'EN_MATCH_VISUAL'
        r['en_visual_score'] = round(top[1], 4); r['en_second_score'] = round(second[1], 4)
        r['en_reason'] = f"시각선택 {top[0]} (top {top[1]:.3f} vs 2등 {second[1]:.3f}, Δ{top[1]-second[1]:.3f})"
        r['en_rejected'] = [s[0] for s in scored[1:]]
        auto += 1
    else:
        r['en_visual_score'] = round(top[1], 4); r['en_second_score'] = round(second[1], 4)
        r['en_reason'] = f"시각 애매(top {top[1]:.3f}/2등 {second[1]:.3f}, Δ{top[1]-second[1]:.3f}) — 사람선택: " + ','.join(s[0] for s in scored)
        keep += 1
    if (i + 1) % 10 == 0:
        print(f"  {i+1}/{len(targets)}", flush=True)

json.dump(data, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)
print(f"\n자동선택 EN_MATCH_VISUAL = {auto} / AMBIGUOUS 유지 = {keep}")
print("\n=== 점수 샘플 (상위 16) ===")
for nm, rar, jp, sc in rows[:16]:
    s = ' '.join(f"{rf}:{v:.3f}" for rf, v in sc)
    print(f"  {nm[:12]:12}[{rar:3}] {jp:13} → {s}")
