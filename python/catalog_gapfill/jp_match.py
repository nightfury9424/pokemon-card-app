"""KO master 253 → JP 후보 매칭 (보조사전 gaps_enriched). 자동확정 빡세게 + scrydex 200 실검증.
 기준=ko_master.json(LOCKED). gaps=보조사전. DB/prod write 0 (jp_match_preview.json 만 생성).

EXACT 승격 = 아래 전부 통과:
  ① base KO명 == base gaps명
  ② candidate_jp_ref prefix ∈ expected_jp_set
  ③ expected_jp_set 안에서 후보 유일
  ④ scrydex 이미지 URL HTTP 200
  ⑤ match_reason 기록
 번호는 hard match 금지(같으면 confidence 근거로 reason에만, 다르면 탈락 X·reason 기록).
 expected_jp_set = prod(BS[:9]↔jp_ref) 우선, 없으면 setcode(wmimages) 변환 보조.
"""
import json, csv, re, os, collections, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

P = os.path.dirname(os.path.abspath(__file__))
UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"
DROP = {'ex', 'gx', 'v', 'vmax', 'vstar', 'vunion', 'v-union', 'prism', 'tag', '★'}


def base(s):
    toks = [t for t in re.split(r'\s+', (s or '').lower()) if t and t not in DROP]
    return re.sub(r'[\s　·.\-_/&「」（）()\[\]]', '', ''.join(toks))


def jp_setpref(ref):
    ref = (ref or '').strip()
    return ref.rsplit('-', 1)[0] if '-' in ref else ref


def setcode_of(img_url):
    m = re.search(r'/wmimages/[^/]+/([^/]+)/[^/]+_\d+\.png', img_url or '')
    return m.group(1) if m else ''


def setcode_to_jp(sc):
    """KO wmimages 세트코드 → scrydex JP set prefix."""
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


def img200(url):
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=15)
        ct = r.headers.get_content_type(); r.read(64)
        return r.status == 200 and ct.startswith('image')
    except Exception:
        return False


# ── prod: KO세트↔JP세트 맵 + jp/en ref 집합 ──
ko2jp = collections.defaultdict(collections.Counter)
prod_jprefs, prod_enrefs = set(), set()
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        code = (r.get('official_card_code') or '').strip()
        jr = (r.get('jp_scrydex_ref') or '').strip()
        er = (r.get('en_scrydex_ref') or '').strip()
        if jr and not jr.startswith('NO_'):
            prod_jprefs.add(jr)
        if er and not er.startswith('NO_'):
            prod_enrefs.add(er)
        if code.startswith('BS') and jr and '-' in jr and not jr.startswith('NO_'):
            ko2jp[code[:9]][jp_setpref(jr)] += 1
ko2jp_top = {k: [s for s, _ in v.most_common()] for k, v in ko2jp.items()}

# ── gaps 보조사전: base KO명 → 후보 ──
gaps = json.load(open(os.path.join(P, 'gaps_enriched.json')))
name_idx = collections.defaultdict(list)
for sect in ('main', 'promo'):
    for c in gaps.get(sect, []):
        if c.get('ko'):
            name_idx[base(c.get('ko'))].append(
                {'ref': c.get('ref'), 'jpset': jp_setpref(c.get('ref')), 'jp': c.get('jp'),
                 'num': c.get('num'), 'set': c.get('set'), 'rarity': c.get('rarity')})

km = json.load(open(os.path.join(P, 'ko_master.json')))

# ── [검증] setcode→jp 변환 vs prod 실데이터 ──
agree = dis = 0
dis_samp = []
for k in km:
    bs = k['code'][:9]
    if bs in ko2jp_top:
        sc = setcode_to_jp(setcode_of(k['ko_image_url']))
        if sc in ko2jp_top[bs]:
            agree += 1
        else:
            dis += 1
            if len(dis_samp) < 8:
                dis_samp.append((k['code'], setcode_of(k['ko_image_url']), sc, ko2jp_top[bs]))
print(f"=== [검증] setcode→jp 변환 vs prod 세트맵: 일치 {agree} / 불일치 {dis} ===")
for c in dis_samp:
    print(f"   {c[0]} setcode={c[1]} →{c[2]}  prod={c[3]}")

# ── 매칭 (200 검증은 뒤에 배치) ──
out = []
for k in km:
    bs = k['code'][:9]
    sc_jp = setcode_to_jp(setcode_of(k['ko_image_url']))
    prod_exp = ko2jp_top.get(bs, [])
    if prod_exp:
        expected, exp_src = prod_exp, 'prod'
        cross = ('setcode일치' if sc_jp in prod_exp else f'setcode({sc_jp})≠prod')
    else:
        expected, exp_src = [sc_jp], 'setcode'
        cross = ''
    raw = name_idx.get(base(k['ko_name']), [])
    seen, cands = set(), []
    for g in raw:
        if g['ref'] in seen:
            continue
        seen.add(g['ref']); cands.append(g)
    in_set = [g for g in cands if g['jpset'] in expected]
    ko_no = str(k['ko_collection_no']).lstrip('0')

    rec = dict(k)
    rec['jp_candidates'] = [{'ref': g['ref'], 'jp': g['jp'], 'jpset': g['jpset'], 'num': g['num'], 'set': g['set']} for g in cands[:8]]
    rec['_expected'] = expected; rec['_exp_src'] = exp_src
    chosen = None
    if not cands:
        rec['jp_conf'], rec['match_reason'] = 'JP_UNRESOLVED', 'gaps base명 일치 없음'
    elif len(in_set) == 1:
        chosen = in_set[0]
        jp_no = str(chosen['num']).lstrip('0')
        numnote = f"번호일치 #{ko_no}" if jp_no == ko_no else f"번호상이 KO#{ko_no}/JP#{jp_no}"
        rec['jp_conf'] = 'JP_PENDING200'   # 200 통과시 EXACT
        rec['match_reason'] = f"이름OK·{exp_src}세트{chosen['jpset']}·유일·{numnote}" + (f"·{cross}" if cross else '')
    elif len(in_set) > 1:
        rec['jp_conf'] = 'JP_MATCH_AMBIGUOUS'
        rec['match_reason'] = f"기대세트{expected}내 {len(in_set)}후보(유일 아님)"
    else:
        rec['jp_conf'] = 'JP_MATCH_AMBIGUOUS'
        rec['match_reason'] = f"이름 {len(cands)}후보, 기대세트{expected}와 prefix 불일치"
    if chosen:
        rec['jp_ref'] = chosen['ref']; rec['jp_name'] = chosen['jp']
        rec['jp_image_url'] = f"https://images.scrydex.com/pokemon/{chosen['ref']}/medium"
    out.append(rec)

# ── scrydex 200 실검증 (PENDING 만) ──
pend = [r for r in out if r['jp_conf'] == 'JP_PENDING200']
print(f"\n=== scrydex 이미지 200 실검증 ({len(pend)}장) ===")
with ThreadPoolExecutor(max_workers=10) as ex:
    futs = {ex.submit(img200, r['jp_image_url']): r for r in pend}
    ok = 0
    for f in as_completed(futs):
        r = futs[f]
        if f.result():
            r['jp_conf'] = 'JP_MATCH_EXACT'; r['match_reason'] += '·scrydex200✓'; ok += 1
        else:
            r['jp_conf'] = 'JP_MATCH_AMBIGUOUS'; r['match_reason'] += '·scrydex200✗(검증실패)'
print(f"   200통과(EXACT 승격)={ok} / 실패(AMBIGUOUS 강등)={len(pend)-ok}")

for r in out:
    for kk in ('_expected', '_exp_src'):
        r.pop(kk, None)
json.dump(out, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)

cnt = collections.Counter(r['jp_conf'] for r in out)
print(f"\n=== JP 매칭 최종 (총 {len(out)}, ko_master.json 미변경) ===")
for k in ['JP_MATCH_EXACT', 'JP_MATCH_AMBIGUOUS', 'JP_UNRESOLVED']:
    print(f"   {k:20} {cnt[k]}")


def show(conf, n):
    rows = [r for r in out if r['jp_conf'] == conf]
    print(f"\n=== {conf} 샘플 ({min(n,len(rows))}/{len(rows)}) ===")
    for r in rows[:n]:
        if conf == 'JP_MATCH_EXACT':
            print(f"   {r['ko_name'][:14]:14} [{r['ko_rarity']}] {r['code']} → {r['jp_ref']} ({r['jp_name']})  | {r['match_reason']}")
        elif conf == 'JP_MATCH_AMBIGUOUS':
            cc = ', '.join(f"{g['ref']}({g['jpset']})" for g in r['jp_candidates'][:5])
            print(f"   {r['ko_name'][:14]:14} [{r['ko_rarity']}] {r['code']} | {r['match_reason']}\n        후보: {cc}")
        else:
            print(f"   {r['ko_name'][:16]:16} [{r['ko_rarity']}] {r['code']} ({r['ko_set_name'][:22]})")


show('JP_MATCH_EXACT', 20)
show('JP_MATCH_AMBIGUOUS', 20)
show('JP_UNRESOLVED', 20)
