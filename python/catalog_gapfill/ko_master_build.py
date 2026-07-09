"""pokemoncard.co.kr 공식 KO master 빌드 → KO-우선 검수 데이터(ko_master.json).

소스: /tmp/crawl_candidates.jsonl (pokemoncard 전세트 크롤, 실제 한국발매 카드만)
필터: 포켓몬/서포트 (아이템/도구/스타디움/에너지 제외)
KO 중복판정: code(BS...) ∈ prod.official_card_code  → 이미 DB에 있음(SKIP)
KO 이미지: cards.image.pokemonkorea.co.kr/data/wmimages/{series}/{setcode}/{setcode}_{num}.png
           (세트당 detail 1회 fetch로 setcode 학습 → 나머지 URL 유도)
KO 상세URL: pokemoncard.co.kr/cards/detail/{code}

pokemoncard 출처 = 태생적으로 KO-verified (일본 독점 프로모 원천 차단).
"""
import json, csv, re, time, urllib.request, os, collections

P = os.path.dirname(os.path.abspath(__file__))
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36"
RE_WM = re.compile(r'(https://cards\.image\.pokemonkorea\.co\.kr/data/wmimages/[^"\']+?/)([A-Za-z0-9]+)_(\d+)\.png')
DETAIL = "https://pokemoncard.co.kr/cards/detail/{}"


def fetch(url, tries=3):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            return urllib.request.urlopen(req, timeout=15).read().decode("utf-8", "ignore")
        except Exception:
            time.sleep(1.2 * (i + 1))
    return None


def is_pokesup(c):
    t = c.get('type', '')
    if any(x in t for x in ('에너지', '도구', '아이템', '스타디움')):
        return False
    if '에너지' in c['name']:
        return False
    return ('포켓몬' in t) or ('서포트' in t)


# ── prod 코드(이미 DB) ──
prod_codes = set()
prod_by_code = {}
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        c = (r.get('official_card_code') or '').strip()
        if c:
            prod_codes.add(c)
            prod_by_code[c] = r

# ── crawl → 포켓몬/서포트 신규 ──
crawl = [json.loads(l) for l in open('/tmp/crawl_candidates.jsonl')]
cands = [c for c in crawl if is_pokesup(c)]
new = [c for c in cands if c['code'] not in prod_codes]
print(f"crawl {len(crawl)} → 포켓몬/서포트 {len(cands)} → prod에 코드없는 신규 {len(new)}")

# ── 세트별 setcode 학습 (세트당 1 fetch) ──
by_set = collections.defaultdict(list)
for c in new:
    by_set[c['code'][:9]].append(c)   # BS+year(4)+seq(3) = 9자
setmap = {}   # set_prefix -> (base_dir, setcode)
print(f"distinct 세트 {len(by_set)}개 — setcode 학습 fetch...")
for sp, items in sorted(by_set.items()):
    probe = items[0]
    h = fetch(DETAIL.format(probe['code']))
    time.sleep(0.4)
    m = RE_WM.search(h) if h else None
    if m:
        setmap[sp] = (m.group(1), m.group(2))
        print(f"  {sp} [{probe['setName'][:24]}] -> {m.group(2)}  ({len(items)}장)")
    else:
        setmap[sp] = None
        print(f"  {sp} [{probe['setName'][:24]}] -> 이미지패턴 실패")

# ── KO master 레코드 ──
out = []
for c in new:
    sp = c['code'][:9]
    sm = setmap.get(sp)
    num3 = str(c['number']).zfill(3)
    img = f"{sm[0]}{sm[1]}_{num3}.png?w=512" if sm else ''
    out.append({
        'code': c['code'], 'ko': c['name'], 'set': c['setName'],
        'num': c['number'], 'rarity': c['rarity'], 'type': c.get('type', ''),
        'ko_img': img, 'ko_detail': DETAIL.format(c['code']),
        'jp_ref': None, 'jp': '', 'jp_img': '',
        'en_ref': None, 'en_name': '', 'en_img': '',
        'verdict': 'ADD',   # KO-verified + prod 코드없음. JP/EN ref dedup 은 다음 단계.
    })

json.dump(out, open(os.path.join(P, 'ko_master.json'), 'w'), ensure_ascii=False, indent=1)
got = sum(1 for o in out if o['ko_img'])
print(f"\nko_master.json: {len(out)}장 (KO이미지 {got}/{len(out)})")
