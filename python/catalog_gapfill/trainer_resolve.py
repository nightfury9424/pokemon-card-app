"""non-RR JP_UNRESOLVED(트레이너) 6장만 별도 처리.
 ko_en_pokemon.json(포켓몬 종족) 으로 못 잡는 트레이너 → scrydex title 에서 EN명 학습.
 ★override 등록 기준 = 구성 ref title 의 '#N' 이 KO 번호와 일치(=그 카드가 맞다는 증거)할 때만.
   내 기억으로 박지 않음. 검증 로그 출력 후 ko_en_trainers_override.json 작성.
 prod/DB write 0.
"""
import json, csv, re, os, collections, urllib.request

P = os.path.dirname(os.path.abspath(__file__))
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


def fetch_title(ref):
    try:
        h = urllib.request.urlopen(urllib.request.Request(
            f"https://scrydex.com/pokemon/cards/_/{ref}", headers={"User-Agent": UA}), timeout=15).read().decode('utf-8', 'ignore')
        m = re.search(r'<title>([^<|]+)', h)
        return m.group(1).strip() if m else ''
    except Exception:
        return ''


# prod 세트맵
ko2jp = collections.defaultdict(collections.Counter)
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        code = (r.get('official_card_code') or '').strip()
        jr = (r.get('jp_scrydex_ref') or '').strip()
        if code.startswith('BS') and jr and '-' in jr and not jr.startswith('NO_'):
            ko2jp[code[:9]][jr.rsplit('-', 1)[0]] += 1
ko2jp_top = {k: [s for s, _ in v.most_common()] for k, v in ko2jp.items()}

data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
unres = [r for r in data if r.get('batch') == 'PRIMARY' and r['jp_conf'] == 'JP_UNRESOLVED']
print(f"=== non-RR JP_UNRESOLVED {len(unres)}장 (트레이너 추정) ===\n")

override = {}
log = []
for r in unres:
    ko_no = str(r['ko_collection_no']).lstrip('0')
    sc_jp = setcode_to_jp(setcode_of(r['ko_image_url']))
    sets = [sc_jp] + [s for s in ko2jp_top.get(r['code'][:9], []) if s != sc_jp]
    picked = None
    for s in sets:
        ref = f"{s}-{ko_no}"
        title = fetch_title(ref)
        tnum = re.search(r'#(\d+)', title)
        tname = re.sub(r'\s*#\d.*$', '', title).strip()
        num_ok = bool(tnum) and tnum.group(1).lstrip('0') == ko_no
        print(f"  {r['code']} | {r['ko_name']} [{r['ko_rarity']}] {r['ko_set_name'][:18]} #{r['ko_collection_no']}")
        print(f"     expected_jp_set={s}  constructed={ref}")
        print(f"     scrydex title='{title}'  → EN='{tname}'  번호일치={'✓' if num_ok else '✗'}")
        if num_ok and tname:
            override[r['ko_name']] = tname
            picked = (ref, tname)
            break
    if picked:
        r['jp_conf'] = 'JP_MATCH_EXACT'
        r['jp_ref'] = picked[0]; r['jp_name'] = picked[1]
        r['jp_image_url'] = f"https://images.scrydex.com/pokemon/{picked[0]}/medium"
        r['match_reason'] = f"트레이너 override·구성 {picked[0]}·title#번호일치·EN={picked[1]}"
        log.append((r['code'], r['ko_name'], '→', picked[0], picked[1], 'OK'))
    else:
        log.append((r['code'], r['ko_name'], '—', '', '', 'MISS(번호불일치/미상)'))
    print()

# override 파일 (검증 통과분만)
json.dump(override, open(os.path.join(P, 'ko_en_trainers_override.json'), 'w'), ensure_ascii=False, indent=1)
print("=== ko_en_trainers_override.json (검증 통과분만) ===")
print(json.dumps(override, ensure_ascii=False, indent=1))

print("\n=== 처리 결과 ===")
for x in log:
    print("  ", x)

json.dump(data, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)
primary = [r for r in data if r.get('batch') == 'PRIMARY']
cnt = collections.Counter(r['jp_conf'] for r in primary)
print(f"\n=== non-RR(PRIMARY {len(primary)}) JP 매칭 갱신 ===")
for k in ['JP_MATCH_EXACT', 'JP_MATCH_AMBIGUOUS', 'JP_UNRESOLVED']:
    print(f"   {k:20} {cnt[k]}")
