"""시리즈 AMBIGUOUS(하이클래스팩=여러 EN세트) → 분포의 후보 EN세트들 전체에서 이름검색해 변종 후보 모음.
 이후 en_visual_disambig.py 가 시각으로 자동선택. write/POST 0.
"""
import json, re, os, collections, urllib.request, html
from concurrent.futures import ThreadPoolExecutor

P = os.path.dirname(os.path.abspath(__file__))
UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"


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


mh = get("https://scrydex.com/pokemon/expansions")
setcode_slug = {}
for slug, sc in re.findall(r'/pokemon/expansions/([a-z0-9-]+)/([a-z0-9]+)"', mh):
    setcode_slug.setdefault(sc, slug)

data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
targets = [r for r in data if r.get('batch') == 'PRIMARY' and r.get('jp_conf') == 'JP_MATCH_EXACT'
           and r.get('en_conf') == 'EN_MATCH_AMBIGUOUS' and not r.get('en_candidates')
           and r.get('series_en_dist')]
print(f"시리즈 AMBIGUOUS 대상 {len(targets)}")

# 후보 EN 세트 수집(분포 count>=2)
need = set()
for r in targets:
    for sc, n in re.findall(r'([a-z0-9]+):(\d+)', r['series_en_dist']):
        if int(n) >= 2:
            need.add(sc)
print(f"후보 EN 세트 {len(need)}개 인덱싱")


def fetch_set(en):
    slug = setcode_slug.get(en)
    if not slug:
        return en, {}
    h = get(f"https://scrydex.com/pokemon/expansions/{slug}/{en}")
    idx = collections.defaultdict(set)
    for s, ref in re.findall(r'/cards/([a-z0-9-]+)/(' + re.escape(en) + r'-\d+[a-z]*)\?variant', h):
        idx[nname(s)].add(ref)
    return en, {k: sorted(v, key=lambda x: int(re.search(r'-(\d+)', x).group(1))) for k, v in idx.items()}


enidx = {}
with ThreadPoolExecutor(max_workers=6) as ex:
    for en, idx in ex.map(fetch_set, need):
        enidx[en] = idx

with ThreadPoolExecutor(max_workers=8) as ex:
    futs = {ex.submit(jp_en_name, r['jp_ref']): r for r in targets if r.get('jp_ref')}
    for f in futs:
        pass
    for f, r in [(f, futs[f]) for f in futs]:
        r['_jpen'] = f.result()

found = 0
for r in targets:
    sets = [sc for sc, n in re.findall(r'([a-z0-9]+):(\d+)', r['series_en_dist']) if int(n) >= 2]
    cands = []
    for s in sets:
        cands += enidx.get(s, {}).get(nname(r.get('_jpen', '')), [])
    cands = list(dict.fromkeys(cands))
    if cands:
        r['en_candidates'] = cands
        r['en_reason'] = f"시리즈 다중세트 {sets} 이름검색 → 변종 {len(cands)}: {','.join(cands)} (시각판별 대기)"
        found += 1
    else:
        r['en_reason'] = f"다중세트 {sets}에 '{r.get('_jpen')}' 없음"

for r in data:
    r.pop('_jpen', None)
json.dump(data, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)
print(f"후보 확보(시각판별 대기) {found} / {len(targets)}")
