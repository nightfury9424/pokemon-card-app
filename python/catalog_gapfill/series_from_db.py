"""한국 productId 기준으로 JP/EN 시리즈를 DB 기존 매핑에서 유도(진실원). scrydex 추론 X.
 각 ADD 후보 productId → 같은 productId(우선) 또는 같은 BS세트(fallback) 기존 prod 카드들의
 jp_scrydex_ref / en_scrydex_ref prefix 분포 → selected prefix + confidence.
 productId 테이블 출력 + jp_match_preview.json 에 시리즈필드 주입. write/POST 0.
"""
import json, csv, os, collections

P = os.path.dirname(os.path.abspath(__file__))


def real(x):
    return bool(x) and not str(x).startswith('NO_')


def pref(ref):
    return ref.rsplit('-', 1)[0] if ref and '-' in ref else None


# prod 카드 → productId별 / BS세트(code[:9])별 jp·en prefix 분포
by_prod_jp = collections.defaultdict(collections.Counter)
by_prod_en = collections.defaultdict(collections.Counter)
by_set_jp = collections.defaultdict(collections.Counter)
by_set_en = collections.defaultdict(collections.Counter)
prod_card_cnt = collections.Counter()
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        pid = r['product_id']; code = (r.get('official_card_code') or '').strip()
        jp = (r.get('jp_scrydex_ref') or '').strip(); en = (r.get('en_scrydex_ref') or '').strip()
        prod_card_cnt[pid] += 1
        if real(jp):
            by_prod_jp[pid][pref(jp)] += 1
            if code.startswith('BS'):
                by_set_jp[code[:9]][pref(jp)] += 1
        if real(en):
            by_prod_en[pid][pref(en)] += 1
            if code.startswith('BS'):
                by_set_en[code[:9]][pref(en)] += 1

prod_name = {}
with open(os.path.join(P, 'prod_products_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        prod_name[r['product_id']] = r['name']


def pick(dist):
    """(selected, confidence, dist_str). confidence: EXACT(단일/지배80%+)/AMBIGUOUS/UNRESOLVED."""
    if not dist:
        return None, 'UNRESOLVED', ''
    items = dist.most_common()
    total = sum(dist.values())
    top, topn = items[0]
    s = ', '.join(f"{k}:{n}" for k, n in items[:5])
    if len(items) == 1 or topn / total >= 0.8:
        return top, 'EXACT', s
    return top, 'AMBIGUOUS', s


def series_for(pid, code):
    """DB_PRODUCT 우선 → DB_SERIES(BS세트) fallback."""
    jp = by_prod_jp.get(pid); en = by_prod_en.get(pid)
    if jp or en:
        sj, cj, dj = pick(jp); se, ce, de = pick(en)
        return dict(jp_set=sj, jp_conf=cj, jp_dist=dj, en_set=se, en_conf=ce, en_dist=de, source='DB_PRODUCT')
    sp = code[:9]
    jp = by_set_jp.get(sp); en = by_set_en.get(sp)
    if jp or en:
        sj, cj, dj = pick(jp); se, ce, de = pick(en)
        return dict(jp_set=sj, jp_conf=cj, jp_dist=dj, en_set=se, en_conf=ce, en_dist=de, source='DB_SERIES')
    return dict(jp_set=None, jp_conf='UNRESOLVED', jp_dist='', en_set=None, en_conf='UNRESOLVED', en_dist='', source='UNRESOLVED')


data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
# KO 세트명 → productId (admin_payload 와 동일 매핑)
import re
def nset(s): return re.sub(r'[\s「」（）()【】]', '', (s or '')).lower()
name2pid = {}
for pid, nm in prod_name.items():
    name2pid.setdefault(nset(nm), pid)

add = [r for r in data if r.get('batch') == 'PRIMARY' and r.get('verdict') == 'ADD' and r.get('jp_conf') == 'JP_MATCH_EXACT']
prod_used = collections.OrderedDict()
for r in data:
    pid = name2pid.get(nset(r['ko_set_name']))
    s = series_for(pid, r['code']) if pid else dict(jp_set=None, jp_conf='UNRESOLVED', jp_dist='', en_set=None, en_conf='UNRESOLVED', en_dist='', source='UNRESOLVED')
    r['series_productId'] = pid
    r['series_jp_set'] = s['jp_set']; r['series_jp_conf'] = s['jp_conf']; r['series_jp_dist'] = s['jp_dist']
    r['series_en_set'] = s['en_set']; r['series_en_conf'] = s['en_conf']; r['series_en_dist'] = s['en_dist']
    r['series_source'] = s['source']
    if r in add and pid and pid not in prod_used:
        prod_used[pid] = s

json.dump(data, open(os.path.join(P, 'jp_match_preview.json'), 'w'), ensure_ascii=False, indent=1)

# ── productId 테이블 (ADD 대상 product) ──
print(f"=== productId → DB 기존 매핑 기준 JP/EN 시리즈 ({len(prod_used)} product, ADD 대상) ===\n")
hdr = f"{'productId':24} {'KO product':30} {'cnt':>4} {'src':10} {'JP set':12} {'jpC':5} {'EN set':12} {'enC'}"
print(hdr); print('-' * len(hdr))
for pid, s in prod_used.items():
    nm = (prod_name.get(pid, '?'))[:28]
    cnt = prod_card_cnt.get(pid, 0)
    print(f"{pid:24} {nm:30} {cnt:>4} {s['source']:10} {str(s['jp_set']):12} {s['jp_conf'][:5]:5} {str(s['en_set']):12} {s['en_conf'][:5]}")
    if s['jp_conf'] == 'AMBIGUOUS' or s['en_conf'] == 'AMBIGUOUS':
        print(f"{'':24} ↳ jp분포[{s['jp_dist']}] en분포[{s['en_dist']}]")

# 요약
ej = sum(1 for s in prod_used.values() if s['jp_conf'] == 'EXACT')
ee = sum(1 for s in prod_used.values() if s['en_conf'] == 'EXACT')
en_un = sum(1 for s in prod_used.values() if s['en_conf'] == 'UNRESOLVED')
print(f"\n[요약] product {len(prod_used)} | JP시리즈 EXACT {ej} | EN시리즈 EXACT {ee} | EN시리즈 UNRESOLVED {en_un}")
# JP 매칭 ref prefix vs DB product 시리즈 교차검증
mis = [r for r in add if r.get('jp_ref') and pref(r['jp_ref']) != r.get('series_jp_set') and r.get('series_jp_set')]
print(f"[교차검증] ADD {len(add)}장 중 JP ref prefix ≠ DB product JP시리즈: {len(mis)}")
for r in mis[:8]:
    print(f"   {r['code']} {r['ko_name']}: jp_ref={r['jp_ref']}(={pref(r['jp_ref'])}) vs DB={r['series_jp_set']} [{r['series_jp_dist']}]")
