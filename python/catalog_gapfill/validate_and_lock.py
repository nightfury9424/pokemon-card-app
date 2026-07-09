"""KO master 검증 + 락. JP/EN 매칭 전에 ko_master.json 을 표준 스키마로 확정한다.
 1) 272→253 필터 차이(제외분) 출력
 2) 표준 필드 검증/표준화
 3) ko_image_url 전수 HTTP 200 검증 + 실패분 per-card detail 재추출
 4) prod official_card_code dedup 위반 0 확인
 5) 표준 스키마로 ko_master.json 재기록(락)
"""
import json, csv, re, time, os, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor, as_completed

P = os.path.dirname(os.path.abspath(__file__))
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36"
RE_WM = re.compile(r'(https://cards\.image\.pokemonkorea\.co\.kr/data/wmimages/[^"\']+?/)([A-Za-z0-9]+)_(\d+)\.png')
DETAIL = "https://pokemoncard.co.kr/cards/detail/{}"


def fetch(url, tries=3):
    for i in range(tries):
        try:
            return urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=15).read().decode("utf-8", "ignore")
        except Exception:
            time.sleep(1.0 * (i + 1))
    return None


def img_ok(url):
    """GET 으로 status 200 + image content-type 확인 (HEAD 미지원 대비)."""
    try:
        r = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=15)
        ct = r.headers.get_content_type()
        r.read(64)
        return r.status == 200 and ct.startswith('image')
    except Exception as e:
        return False


# ── prod codes ──
prod_codes = set()
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        c = (r.get('official_card_code') or '').strip()
        if c:
            prod_codes.add(c)

# ── 1) 272→253 필터 차이 ──
crawl = [json.loads(l) for l in open('/tmp/crawl_candidates.jsonl')]


def loose(c):  # 초기 ad-hoc 필터 (272 기준)
    t = c.get('type', '')
    return ('포켓몬' in t or '서포트' in t) and '에너지' not in c['name']


def strict(c):  # 최종 is_pokesup (253 기준)
    t = c.get('type', '')
    if any(x in t for x in ('에너지', '도구', '아이템', '스타디움')):
        return False
    if '에너지' in c['name']:
        return False
    return ('포켓몬' in t) or ('서포트' in t)


loose_new = [c for c in crawl if loose(c) and c['code'] not in prod_codes]
strict_new = [c for c in crawl if strict(c) and c['code'] not in prod_codes]
excluded = [c for c in loose_new if c not in strict_new]
print(f"=== 1) 필터 차이 ===  loose(272)={len(loose_new)}  strict(253)={len(strict_new)}  제외={len(excluded)}")
from collections import Counter
print("   제외분 type 분포:", dict(Counter(c['type'] for c in excluded)))
for c in excluded:
    print(f"     - {c['code']} [{c['rarity']}] {c['name']}  ({c['type']})")

# ── 2) 표준 스키마화 ──
def to_setcode_base(items):
    """세트당 1 detail fetch → (base_dir, setcode)."""
    h = fetch(DETAIL.format(items[0]['code']))
    m = RE_WM.search(h) if h else None
    return (m.group(1), m.group(2)) if m else None


by_set = {}
for c in strict_new:
    by_set.setdefault(c['code'][:9], []).append(c)
setmap = {}
print(f"\n=== 2) 표준화: {len(by_set)} 세트 setcode 학습 ===")
for sp, items in sorted(by_set.items()):
    setmap[sp] = to_setcode_base(items)
    time.sleep(0.3)

records = []
for c in strict_new:
    sm = setmap.get(c['code'][:9])
    num3 = str(c['number']).zfill(3)
    img = f"{sm[0]}{sm[1]}_{num3}.png?w=512" if sm else ''
    records.append({
        'code': c['code'], 'ko_name': c['name'], 'ko_set_name': c['setName'],
        'ko_collection_no': c['number'], 'ko_rarity': c['rarity'], 'type': c.get('type', ''),
        'ko_image_url': img, 'ko_detail_url': DETAIL.format(c['code']),
        'jp_ref': None, 'jp_name': '', 'jp_image_url': '', 'jp_conf': 'JP_UNRESOLVED',
        'en_ref': None, 'en_name': '', 'en_image_url': '', 'en_conf': 'EN_UNRESOLVED',
        'verdict': 'ADD',
    })

REQ = ['code', 'ko_name', 'ko_set_name', 'ko_collection_no', 'ko_rarity', 'ko_image_url', 'ko_detail_url', 'type']
missing = [(r['code'], k) for r in records for k in REQ if not r.get(k)]
print(f"   필수필드 누락: {len(missing)}", missing[:10])

# ── 3) 이미지 전수 HTTP 200 ──
print(f"\n=== 3) 이미지 HTTP 200 전수검증 ({len(records)}장) ===")
fails = []
with ThreadPoolExecutor(max_workers=10) as ex:
    futs = {ex.submit(img_ok, r['ko_image_url']): r for r in records if r['ko_image_url']}
    for f in as_completed(futs):
        if not f.result():
            fails.append(futs[f])
print(f"   1차: 200={len(records)-len(fails)} / fail={len(fails)}")
# 실패분 per-card detail 재추출
repaired = 0
for r in fails:
    h = fetch(r['ko_detail_url'])
    m = RE_WM.search(h) if h else None
    if m:
        url = f"{m.group(1)}{m.group(2)}_{m.group(3)}.png?w=512"
        if img_ok(url):
            r['ko_image_url'] = url
            repaired += 1
    time.sleep(0.3)
still = [r for r in fails if not img_ok(r['ko_image_url'])]
print(f"   재추출 복구={repaired} / 최종 실패={len(still)}")
for r in still:
    print(f"     ✗ {r['code']} {r['ko_name']}  {r['ko_image_url']}")

# ── 4) prod 코드 dedup ──
viol = [r for r in records if r['code'] in prod_codes]
print(f"\n=== 4) prod 코드 dedup 위반: {len(viol)} (0이어야 함) ===")

# ── 5) 락 ──
json.dump(records, open(os.path.join(P, 'ko_master.json'), 'w'), ensure_ascii=False, indent=1)
print(f"\n=== 5) LOCK ===  ko_master.json {len(records)}장 확정 "
      f"(이미지 200 {len(records)-len(still)}/{len(records)}, 위반 {len(viol)}, 필드누락 {len(missing)})")
