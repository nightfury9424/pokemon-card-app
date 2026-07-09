"""JP_MATCH_EXACT 83장 → EN 매칭 + prod 2차 dedup. 번호 hard-match 금지(EN#≠JP#).
 EN_MATCH_EXACT = JP영문명 == EN세트 카드영문명 · EN세트내 유일 · ref/이미지 실재(expansion HTML 출처).
 EN ref 는 prod JP→EN 세트맵 → scrydex expansion 페이지(영문명↔ref)에서 이름매칭으로 획득(EN# 구성 X).
 dedup: jp_ref∈prod.jp → EXCLUDE_JP / en_ref∈prod.en → EXCLUDE_EN / 아니면 ADD.  DB write 0.
"""
import json, csv, re, os, collections, urllib.request
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
    """JP scrydex title 의 영문 카드명(# 앞)."""
    h = get(f"https://scrydex.com/pokemon/cards/_/{ref}")
    m = re.search(r'<title>([^<|]+)', h)
    return re.sub(r'\s*#\d.*$', '', m.group(1)).strip() if m else ''


# ── prod: JP→EN 세트맵, jp/en ref 집합 ──
jp2en = collections.defaultdict(collections.Counter)
prod_jprefs, prod_enrefs = set(), set()
prod_en_by = {}
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        jr = (r.get('jp_scrydex_ref') or '').strip(); er = (r.get('en_scrydex_ref') or '').strip()
        if jr and not jr.startswith('NO_'):
            prod_jprefs.add(jr)
        if er and not er.startswith('NO_'):
            prod_enrefs.add(er); prod_en_by[er] = r
        if jr and er and '-' in jr and '-' in er and not er.startswith('NO_') and not jr.startswith('NO_'):
            jp2en[jr.rsplit('-', 1)[0]][er.rsplit('-', 1)[0]] += 1
jp2en_top = {k: v.most_common(1)[0][0] for k, v in jp2en.items()}

# ── master expansions: EN setcode → slug ──
mh = get("https://scrydex.com/pokemon/expansions")
setcode_slug = {}
for slug, sc in re.findall(r'/pokemon/expansions/([a-z0-9-]+)/([a-z0-9]+)"', mh):
    setcode_slug.setdefault(sc, slug)

data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
targets = [r for r in data if r.get('batch') == 'PRIMARY' and r['jp_conf'] == 'JP_MATCH_EXACT']
print(f"EN 매칭 대상(JP_MATCH_EXACT) {len(targets)}장")

# 필요한 EN 세트
en_sets = {}
for r in targets:
    js = (r.get('jp_ref') or '').rsplit('-', 1)[0]
    en = jp2en_top.get(js)
    r['_enset'] = en
    if en:
        en_sets[en] = setcode_slug.get(en)
print(f"필요 EN 세트 {len(en_sets)}개: " + ', '.join(f"{k}({v})" for k, v in list(en_sets.items())[:12]))


def fetch_enset(en, slug):
    if not slug:
        return en, {}
    h = get(f"https://scrydex.com/pokemon/expansions/{slug}/{en}")
    idx = collections.defaultdict(list)
    for ref, name, num in re.findall(r'/cards/[^/]+/(' + re.escape(en) + r'-\w+)\?variant[^"]*"[\s\S]{0,400}?<span[^>]*>([^<]+?) #(\d+)</span>', h):
        idx[nname(name)].append((ref, name.strip(), num))
    return en, idx


print("EN 세트 expansion 페이지 인덱싱...")
enidx = {}
with ThreadPoolExecutor(max_workers=6) as ex:
    for en, idx in ex.map(lambda kv: fetch_enset(*kv), en_sets.items()):
        enidx[en] = idx
        print(f"   {en}: {sum(len(v) for v in idx.values())} 카드")

# JP 영문명 확보(병렬)
print(f"\nJP 영문명 fetch ({len(targets)})...")
with ThreadPoolExecutor(max_workers=8) as ex:
    futs = {ex.submit(jp_en_name, r['jp_ref']): r for r in targets}
    for f in as_completed(futs):
        futs[f]['_jpen'] = f.result()

# ── EN 매칭 ──
for r in targets:
    en = r['_enset']; jpen = r.get('_jpen', '')
    if not en or en not in enidx:
        r['en_conf'], r['en_reason'] = 'EN_UNRESOLVED', f'EN세트 미상(jpset→{en})'
        continue
    cands = enidx[en].get(nname(jpen), [])
    cands = list({c[0]: c for c in cands}.values())
    if len(cands) == 1:
        ref, name, num = cands[0]
        r['en_ref'] = ref; r['en_name'] = name
        r['en_image_url'] = f"https://images.scrydex.com/pokemon/{ref}/medium"
        r['en_conf'] = 'EN_MATCH_EXACT'
        r['en_reason'] = f"이름'{jpen}'·{en}세트 유일·{ref}(EN#{num})"
    elif len(cands) > 1:
        r['en_conf'] = 'EN_MATCH_AMBIGUOUS'
        r['en_reason'] = f"{en}세트내 동명 {len(cands)}후보: " + ','.join(c[0] for c in cands[:5])
        r['en_candidates'] = [c[0] for c in cands]
    else:
        r['en_conf'] = 'EN_UNRESOLVED'
        r['en_reason'] = f"{en}세트에 '{jpen}' 영문명 없음"

# ── prod 2차 dedup (전체 PRIMARY) ──
for r in data:
    if r.get('batch') != 'PRIMARY':
        continue
    jr = r.get('jp_ref'); er = r.get('en_ref')
    if jr and jr in prod_jprefs:
        r['verdict'] = 'EXCLUDE_JP'
        ex = next((x for x in prod_en_by.values() if x['jp_scrydex_ref'] == jr), None)
    elif er and er in prod_enrefs:
        r['verdict'] = 'EXCLUDE_EN'
    else:
        r['verdict'] = 'ADD'

for r in data:
    for k in ('_enset', '_jpen'):
        r.pop(k, None)
json.dump(data, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)

prim = [r for r in data if r.get('batch') == 'PRIMARY']
enc = collections.Counter(r.get('en_conf', '-') for r in targets)
vc = collections.Counter(r.get('verdict', '-') for r in prim)
print(f"\n=== EN 매칭 (대상 {len(targets)}) ===")
for k in ['EN_MATCH_EXACT', 'EN_MATCH_AMBIGUOUS', 'EN_UNRESOLVED']:
    print(f"   {k:20} {enc[k]}")
print(f"=== prod 2차 dedup (PRIMARY {len(prim)}) ===")
for k in ['ADD', 'EXCLUDE_JP', 'EXCLUDE_EN']:
    print(f"   {k:12} {vc[k]}")
print("\n--- EN_MATCH_EXACT 샘플 12 ---")
for r in [x for x in targets if x.get('en_conf') == 'EN_MATCH_EXACT'][:12]:
    print(f"   {r['ko_name'][:13]:13} {r['jp_ref']:13} → EN {r['en_ref']:12} | {r['en_reason']}")
print("--- EN_UNRESOLVED 샘플 8 ---")
for r in [x for x in targets if x.get('en_conf') == 'EN_UNRESOLVED'][:8]:
    print(f"   {r['ko_name'][:13]:13} {r['jp_ref']:13} | {r['en_reason']}")
