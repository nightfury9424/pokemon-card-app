"""RR 보류(DEFER_RR) + non-RR 대상 직접 scrydex 구성검증.
 입력: jp_match_preview.json(1차 gaps 매칭 결과) + ko_master.json
 RR(ko_rarity=='RR') → batch=DEFER_RR, 1차 제외(삭제 X).
 non-RR 중 아직 EXACT 아닌 카드 → 구성검증:
   expected_jp_set({setcode_jp} 우선 + prod맵) 별로 ref={set}-{ko_num} 구성
   → scrydex 페이지 fetch → title 영문명 ⊃ 기대 종족명(ko_en) AND 200 → JP_MATCH_EXACT(construct)
   아니면 기존 conf 유지. prod/DB write 0.
"""
import json, csv, re, os, collections, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

P = os.path.dirname(os.path.abspath(__file__))
BASE = os.path.dirname(P)  # python/
UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"


def setcode_of(u):
    m = re.search(r'/wmimages/[^/]+/([^/]+)/[^/]+_\d+\.png', u or '')
    return m.group(1) if m else ''


def setcode_to_jp(sc):
    s = sc.lower()
    if s.startswith(('sv', 'sm', 'xy')):
        jp = s
    elif s.startswith('m'):
        jp = s
    elif s.startswith('s'):
        jp = 'swsh' + s[1:]
    else:
        jp = s
    return jp + '_ja'


# KO→EN 종족 사전 (긴 키 우선 substring)
ko_en = json.load(open(os.path.join(BASE, '..', 'scanner', 'data', 'ko_en_pokemon.json')))
keys_by_len = sorted(ko_en.keys(), key=len, reverse=True)


def expected_en(ko_name):
    n = (ko_name or '').replace(' ', '')
    for k in keys_by_len:
        if k and k in n:
            return ko_en[k]
    return None


# prod KO세트↔JP세트 맵
ko2jp = collections.defaultdict(collections.Counter)
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        code = (r.get('official_card_code') or '').strip()
        jr = (r.get('jp_scrydex_ref') or '').strip()
        if code.startswith('BS') and jr and '-' in jr and not jr.startswith('NO_'):
            ko2jp[code[:9]][jr.rsplit('-', 1)[0]] += 1
ko2jp_top = {k: [s for s, _ in v.most_common()] for k, v in ko2jp.items()}


def verify(ref, en):
    """scrydex 페이지 200 + title 영문명 ⊃ en. 반환: title(성공) or None."""
    try:
        h = urllib.request.urlopen(urllib.request.Request(
            f"https://scrydex.com/pokemon/cards/_/{ref}", headers={"User-Agent": UA}), timeout=15).read().decode('utf-8', 'ignore')
        m = re.search(r'<title>([^<|]+)', h)
        title = m.group(1).strip() if m else ''
        if en and en.lower() in title.lower():
            return title
    except Exception:
        pass
    return None


data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
for r in data:
    r['batch'] = 'DEFER_RR' if r['ko_rarity'] == 'RR' else 'PRIMARY'

primary = [r for r in data if r['batch'] == 'PRIMARY']
deferred = [r for r in data if r['batch'] == 'DEFER_RR']
todo = [r for r in primary if r['jp_conf'] != 'JP_MATCH_EXACT']
print(f"전체 {len(data)} | non-RR(PRIMARY) {len(primary)} | RR보류 {len(deferred)}")
print(f"non-RR 중 기존 EXACT {len(primary)-len(todo)} | 구성검증 대상 {len(todo)}")


def attempt(r):
    en = expected_en(r['ko_name'])
    if not en:
        return r, None, None, 'EN종족명 미상(테마/트레이너)'
    ko_no = str(r['ko_collection_no']).lstrip('0')
    sets = []
    sc = setcode_to_jp(setcode_of(r['ko_image_url']))
    sets.append(sc)
    for s in ko2jp_top.get(r['code'][:9], []):
        if s not in sets:
            sets.append(s)
    for s in sets:
        ref = f"{s}-{ko_no}"
        title = verify(ref, en)
        if title:
            return r, ref, title, f"구성 {ref}·title⊃{en}·200✓"
    return r, None, None, f"구성검증 실패(en={en}, tried {sets}#{ko_no})"


print(f"\n=== 구성검증 fetch ({len(todo)}장) ===")
prom = 0
with ThreadPoolExecutor(max_workers=8) as ex:
    futs = [ex.submit(attempt, r) for r in todo]
    for f in as_completed(futs):
        r, ref, title, reason = f.result()
        if ref:
            r['jp_conf'] = 'JP_MATCH_EXACT'
            r['jp_ref'] = ref
            r['jp_name'] = title
            r['jp_image_url'] = f"https://images.scrydex.com/pokemon/{ref}/medium"
            r['match_reason'] = reason
            prom += 1
        else:
            r['construct_note'] = reason
print(f"   구성검증 EXACT 승격 = {prom} / 실패 = {len(todo)-prom}")

json.dump(data, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)

cnt = collections.Counter(r['jp_conf'] for r in primary)
print(f"\n=== non-RR(PRIMARY {len(primary)}) 최종 ===")
for k in ['JP_MATCH_EXACT', 'JP_MATCH_AMBIGUOUS', 'JP_UNRESOLVED']:
    print(f"   {k:20} {cnt[k]}")
print(f"=== DEFER_RR (보류) {len(deferred)} ===")


def show(conf, n):
    rows = [r for r in primary if r['jp_conf'] == conf]
    print(f"\n--- {conf} 샘플 ({min(n,len(rows))}/{len(rows)}) ---")
    for r in rows[:n]:
        if conf == 'JP_MATCH_EXACT':
            print(f"   {r['ko_name'][:15]:15}[{r['ko_rarity']:3}] {r['code']} → {r['jp_ref']:14} | {r['match_reason']}")
        else:
            print(f"   {r['ko_name'][:15]:15}[{r['ko_rarity']:3}] {r['code']} ({r['ko_set_name'][:20]}) | {r.get('construct_note') or r.get('match_reason')}")


show('JP_MATCH_EXACT', 24)
show('JP_MATCH_AMBIGUOUS', 16)
show('JP_UNRESOLVED', 16)
