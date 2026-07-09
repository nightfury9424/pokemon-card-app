"""DB 확정 EN 시리즈 안으로 들어가 JP title 영문명으로 EN ref 탐색 (DB 우선, scrydex는 카드목록만).
 정적 href `/cards/{slug}/{ref}` 추출(전체 카드 잡힘 — JS렌더 불요).
 대상 = PRIMARY · jp_conf EXACT · series_en_conf==EXACT.
 EN_MATCH_EXACT = 시리즈내 영문명(slug) 유일 + 이미지200. 복수변종=AMBIGUOUS, 없음=UNRESOLVED.
 series_en_conf!=EXACT → EN_MATCH_AMBIGUOUS/UNRESOLVED(시리즈 단계서 보류). write/POST 0.
"""
import json, re, os, collections, urllib.request, html
from concurrent.futures import ThreadPoolExecutor, as_completed

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
    if not m:
        return ''
    return re.sub(r'\s*#\d.*$', '', html.unescape(m.group(1))).strip()


def img200(url):
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=15)
        ct = r.headers.get_content_type(); r.read(32)
        return r.status == 200 and ct.startswith('image')
    except Exception:
        return False


# master: EN setcode → slug
mh = get("https://scrydex.com/pokemon/expansions")
setcode_slug = {}
for slug, sc in re.findall(r'/pokemon/expansions/([a-z0-9-]+)/([a-z0-9]+)"', mh):
    setcode_slug.setdefault(sc, slug)

data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
targets = [r for r in data if r.get('batch') == 'PRIMARY' and r.get('jp_conf') == 'JP_MATCH_EXACT']

# 필요 EN 세트(DB 시리즈 EXACT)
need = {}
for r in targets:
    if r.get('series_en_conf') == 'EXACT' and r.get('series_en_set'):
        need[r['series_en_set']] = setcode_slug.get(r['series_en_set'])
print(f"대상 {len(targets)} | EN시리즈 EXACT 세트 {len(need)}개")


def fetch_set(en, slug):
    if not slug:
        return en, {}
    h = get(f"https://scrydex.com/pokemon/expansions/{slug}/{en}")
    idx = collections.defaultdict(set)
    for s, ref in re.findall(r'/cards/([a-z0-9-]+)/(' + re.escape(en) + r'-\d+[a-z]*)\?variant', h):
        idx[nname(s)].add(ref)
    return en, {k: sorted(v, key=lambda x: int(re.search(r'-(\d+)', x).group(1))) for k, v in idx.items()}


enidx = {}
with ThreadPoolExecutor(max_workers=6) as ex:
    for en, idx in ex.map(lambda kv: fetch_set(*kv), need.items()):
        enidx[en] = idx
        print(f"   {en}({need[en]}): {sum(len(v) for v in idx.values())} ref / {len(idx)} 이름")

# JP 영문명
with ThreadPoolExecutor(max_workers=8) as exx:
    futs = {exx.submit(jp_en_name, r['jp_ref']): r for r in targets if r.get('jp_ref')}
    for f in as_completed(futs):
        futs[f]['_jpen'] = f.result()

pend_exact = []
for r in targets:
    en_set = r.get('series_en_set'); sconf = r.get('series_en_conf')
    jpen = r.get('_jpen', '')
    if not en_set or sconf == 'UNRESOLVED':
        r['en_conf'] = 'EN_UNRESOLVED'; r['en_reason'] = f'DB EN시리즈 없음({sconf})'
        continue
    if sconf == 'AMBIGUOUS':
        r['en_conf'] = 'EN_MATCH_AMBIGUOUS'; r['en_reason'] = f'DB EN시리즈 AMBIGUOUS({r.get("series_en_dist")}) — 시리즈 단계 보류'
        continue
    cands = enidx.get(en_set, {}).get(nname(jpen), [])
    if len(cands) == 1:
        r['_pend'] = (cands[0], jpen, en_set); pend_exact.append(r)
    elif len(cands) > 1:
        r['en_conf'] = 'EN_MATCH_AMBIGUOUS'; r['en_candidates'] = cands
        r['en_reason'] = f"'{jpen}' {en_set}내 변종 {len(cands)}: {','.join(cands)}"
    else:
        r['en_conf'] = 'EN_UNRESOLVED'; r['en_reason'] = f"{en_set}에 '{jpen}' 영문명 없음"

# 이미지 200 검증 → EXACT
with ThreadPoolExecutor(max_workers=10) as exx:
    futs = {exx.submit(img200, f"https://images.scrydex.com/pokemon/{r['_pend'][0]}/medium"): r for r in pend_exact}
    for f in as_completed(futs):
        r = futs[f]; ref, jpen, en_set = r['_pend']
        if f.result():
            r['en_ref'] = ref; r['en_name'] = jpen
            r['en_image_url'] = f"https://images.scrydex.com/pokemon/{ref}/medium"
            r['en_conf'] = 'EN_MATCH_EXACT'; r['en_reason'] = f"DB시리즈 {en_set}·'{jpen}' 유일·{ref}·200✓"
        else:
            r['en_conf'] = 'EN_UNRESOLVED'; r['en_reason'] = f"{ref} 이미지 200 실패"

for r in data:
    r.pop('_jpen', None); r.pop('_pend', None)
json.dump(data, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)

c = collections.Counter(r.get('en_conf', '-') for r in targets)
print(f"\n=== EN 매칭 (DB시리즈 기반, 대상 {len(targets)}) ===")
for k in ['EN_MATCH_EXACT', 'EN_MATCH_AMBIGUOUS', 'EN_UNRESOLVED']:
    print(f"   {k:20} {c[k]}")
print("\n--- EXACT 샘플 12 ---")
for r in [x for x in targets if x.get('en_conf') == 'EN_MATCH_EXACT'][:12]:
    print(f"   {r['ko_name'][:13]:13} {r['jp_ref']:13} → {r['en_ref']:12} | {r['en_reason']}")
print("--- AMBIGUOUS(변종) 샘플 8 ---")
for r in [x for x in targets if x.get('en_conf') == 'EN_MATCH_AMBIGUOUS' and x.get('en_candidates')][:8]:
    print(f"   {r['ko_name'][:13]:13} [{r['ko_rarity']:3}] {r['jp_ref']:13} | {r['en_reason']}")
print("--- UNRESOLVED 샘플 6 ---")
for r in [x for x in targets if x.get('en_conf') == 'EN_UNRESOLVED'][:6]:
    print(f"   {r['ko_name'][:13]:13} {r['jp_ref']:13} | {r['en_reason']}")
