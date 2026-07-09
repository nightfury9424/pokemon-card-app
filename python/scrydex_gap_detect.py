"""scrydex 기반 카탈로그 갭 탐지 — 전체 세트의 누락 chase 포켓몬+서포터 찾기.
입력: /tmp/catalog.tsv (KO 카드 덤프). 출력: /tmp/gaps.tsv (검수용).
필터: supertype=ポケモン OR (トレーナー+支援서포터). 커먼/언커먼/레어 제외(=chase만).
크롤: scrydex data-terminal-trigger-json-value JSON 파싱, ThreadPoolExecutor 동시.
"""
import csv, collections, re, json, html, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

UA = {'User-Agent': 'Mozilla/5.0'}
EXCLUDE_RAR = {'コモン', 'アンコモン', 'レア'}   # 베이스 커먼 → 나머지=chase

# 1. 카탈로그 → 세트별 jp 세트코드 + 가진 번호(jp ref 번호)
sets = collections.defaultdict(lambda: {'jpcode': None, 'nums': set(), 'pname': ''})
for r in csv.reader(open('/tmp/catalog.tsv'), delimiter='\t'):
    if len(r) < 9:
        continue
    pid, pname, jp = r[0], r[1], r[2]
    s = sets[pid]; s['pname'] = pname
    if jp:
        if not s['jpcode']:
            s['jpcode'] = jp.rsplit('-', 1)[0]
        m = re.search(r'-(\d+)$', jp)
        if m:
            s['nums'].add(int(m.group(1)))

# 2. 후보 번호 = 가진 범위의 구멍 + max 너머 12개
tasks = []
nsets = 0
for s in sets.values():
    if not s['jpcode'] or not s['nums']:
        continue
    nsets += 1
    lo, hi = min(s['nums']), max(s['nums'])
    cand = (set(range(lo, hi + 1)) - s['nums']) | set(range(hi + 1, hi + 13))
    for n in cand:
        tasks.append((s['jpcode'], n, s['pname']))
print(f"세트 {nsets} / 크롤 후보 {len(tasks)}개", flush=True)

# 3. 크롤 + 필터
def crawl(t):
    code, n, pname = t
    ref = f"{code}-{n}"
    try:
        req = urllib.request.Request(f"https://scrydex.com/pokemon/cards/_/{ref}", headers=UA)
        h = urllib.request.urlopen(req, timeout=15).read().decode('utf-8', 'ignore')
        m = re.search(r'data-terminal-trigger-json-value="([^"]+)"', h)
        if not m:
            return None
        d = json.loads(html.unescape(m.group(1))).get('data', {})
        if str(d.get('id', '')) != ref:
            return None
        sup = d.get('supertype', ''); subs = d.get('subtypes', []) or []; rar = d.get('rarity', '')
        if rar in EXCLUDE_RAR:
            return None                                    # 커먼 제외
        if not (sup == 'ポケモン' or (sup == 'トレーナー' and '支援' in subs)):
            return None                                    # 포켓몬/서포터만
        dex = ','.join(str(x) for x in (d.get('national_pokedex_numbers') or []))
        return (pname, n, ref, d.get('name', ''), sup, '|'.join(subs),
                rar, d.get('rarity_code', ''), dex)
    except Exception:
        return None

found = 0
with open('/tmp/gaps.tsv', 'w') as out, ThreadPoolExecutor(max_workers=14) as ex:
    futs = [ex.submit(crawl, t) for t in tasks]
    for i, f in enumerate(as_completed(futs)):
        r = f.result()
        if r:
            out.write('\t'.join(str(x) for x in r) + '\n'); out.flush(); found += 1
        if i % 500 == 0:
            print(f"  {i}/{len(tasks)} · 갭 {found}", flush=True)
print(f"완료: 갭 {found}장 → /tmp/gaps.tsv", flush=True)
