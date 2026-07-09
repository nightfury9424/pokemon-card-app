"""scrydex JP 세트 전수 갭 — KO 미발매 최신 세트(m3_ja/m4_ja/m5_ja 등) 누락 고레어 탐지.

배경(2026-06-20 실측 확정):
  ★닌자스피너(m4_ja) 같은 최신 세트는 KO 미발매 → pokemoncard.co.kr엔 base 83장뿐·chase 0.
   우리 DB엔 이미 JP ref(m4_ja-N)로 36/120 들어와 있으나 official_card_code 빈칸·NO_EN.
  → 이런 세트는 pokemoncard 불가, **scrydex JP가 유일·최속 소스**.

검증된 scrydex 메소드(실측):
  - expansions 인덱스: `https://scrydex.com/pokemon/expansions` = 정적, 368세트 (slug, code) 한 방.
    예: ('ninja-spinner', 'm4_ja'). m*_ja = JP 신세트.
  - 세트 페이지: `/pokemon/expansions/{slug}/{code}` = ★정적 1요청에 **전체 카드**(120장) ref+slug(EN명)+이미지.
    카드당 0.4s씩 긁는 pokemoncard보다 압도적 빠름.
  - 카드 디테일: `/pokemon/cards/_/{ref}` title="Watchog #95 - Ninja Spinner | Pokémon | Japanese"
    → EN명·번호·세트·레어도("Art Rare") 전부. 누락분만 fetch.

고레어 필터 = scrydex_gap_detect.py와 동일 정책: 레어도 ∉ {Common, Uncommon, Rare} = chase.

사용:
  python scrydex_set_gap.py --list-jp                 # JP(m*_ja 등) 세트 목록
  python scrydex_set_gap.py --jp-set m4_ja            # 단일 세트 갭
  python scrydex_set_gap.py --jp-set m3_ja m4_ja m5_ja
  python scrydex_set_gap.py --jp-set m4_ja --include-low   # 커먼까지 전부(기본=고레어만)

출력: scrydex_set_gap_missing.csv (jp_ref,num,en_slug,en_name,number,rarity,is_high,img,in_db)
DB/POST write 0.
"""
import csv, os, re, sys, time, argparse, collections, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

P = os.path.dirname(os.path.abspath(__file__))
UA = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"}
LOW = {'common', 'uncommon', 'rare'}   # 이것만 제외 = 나머지 chase
SCRY_RAR = {  # scrydex 표기 → 우리 코드(근사)
    'double rare': 'RR', 'art rare': 'AR', 'special art rare': 'SAR',
    'super rare': 'SR', 'ultra rare': 'UR', 'hyper rare': 'HR',
    'shiny rare': 'S', 'shiny super rare': 'SSR', 'illustration rare': 'AR',
    'special illustration rare': 'SAR', 'rare': 'R', 'uncommon': 'U', 'common': 'C',
}

def get(u):
    try:
        return urllib.request.urlopen(urllib.request.Request(u, headers=UA), timeout=25).read().decode('utf-8', 'ignore')
    except Exception as e:
        return None

def load_holdings():
    """jp_scrydex_ref 보유 set."""
    have = set()
    for r in csv.DictReader(open(os.path.join(P, 'prod_cards_snapshot.csv'))):
        j = r['jp_scrydex_ref'].strip()
        if j:
            have.add(j)
    return have

def expansions_index():
    """(slug, code) 전체."""
    h = get("https://scrydex.com/pokemon/expansions")
    if not h:
        print("expansions 인덱스 fetch 실패"); sys.exit(2)
    pairs = re.findall(r'/pokemon/expansions/([a-z0-9-]+)/([a-z0-9_]+)"', h)
    return {code: slug for slug, code in pairs}   # code→slug

def set_cards(slug, code):
    """세트 페이지 → [(ref, num, en_slug)] 정적 1요청."""
    h = get(f"https://scrydex.com/pokemon/expansions/{slug}/{code}")
    if not h:
        return []
    out = {}
    for en_slug, ref in re.findall(r'/pokemon/cards/([a-z0-9-]+)/(' + re.escape(code) + r'-\d+[a-z]*)', h):
        m = re.match(re.escape(code) + r'-(\d+)', ref)
        if m:
            out[ref] = (int(m.group(1)), en_slug)
    return [(ref, n, s) for ref, (n, s) in sorted(out.items(), key=lambda x: x[1][0])]

def card_detail(ref):
    """디테일 → (en_name, number, rarity_raw)."""
    d = get(f"https://scrydex.com/pokemon/cards/_/{ref}")
    if not d:
        return ('?', '?', '?')
    t = re.search(r'<title>([^<]+)</title>', d)
    name, number = '?', '?'
    if t:
        mm = re.match(r'\s*(.+?)\s*#(\S+)\s*-', t.group(1))
        if mm:
            name, number = mm.group(1), mm.group(2)
    rar = '?'
    mr = re.search(r'>(Double Rare|Special Art Rare|Special Illustration Rare|Art Rare|Illustration Rare|Super Rare|Ultra Rare|Hyper Rare|Shiny Super Rare|Shiny Rare|Rare|Uncommon|Common)<', d)
    if mr:
        rar = mr.group(1)
    return (name, number, rar)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--jp-set', nargs='*', help='JP 세트코드(예 m4_ja)')
    ap.add_argument('--list-jp', action='store_true')
    ap.add_argument('--include-low', action='store_true', help='커먼/언커먼/레어까지 전부')
    ap.add_argument('--workers', type=int, default=4)
    args = ap.parse_args()

    idx = expansions_index()
    if args.list_jp:
        jp = sorted(c for c in idx if c.endswith('_ja') or re.match(r'm\d', c))
        print(f"JP/신세트 코드 {len(jp)}개:")
        for c in jp:
            print(f"  {c:12} slug={idx[c]}")
        return

    if not args.jp_set:
        print("--jp-set <code...> 또는 --list-jp"); return

    have = load_holdings()
    all_rows = []
    for code in args.jp_set:
        slug = idx.get(code)
        if not slug:
            print(f"  ⚠ {code}: expansions 인덱스에 없음 (코드 확인)"); continue
        cards = set_cards(slug, code)
        missing = [(ref, n, s) for ref, n, s in cards if ref not in have]
        held = len(cards) - len(missing)
        print(f"\n=== {code} ({slug}) scrydex {len(cards)}장 · 보유 {held} · 누락 {len(missing)} ===")
        # 누락분만 디테일 fetch (레어도/이름)
        rows = []
        def work(item):
            ref, n, s = item
            time.sleep(0.3)
            nm, num, rar = card_detail(ref)
            return dict(jp_ref=ref, num=n, en_slug=s, en_name=nm, number=num,
                        rarity=rar, is_high=(rar.lower() not in LOW and rar != '?'),
                        img=f"https://images.scrydex.com/pokemon/{ref}/medium", in_db='N')
        with ThreadPoolExecutor(max_workers=args.workers) as ex:
            for r in ex.map(work, missing):
                rows.append(r)
        rows.sort(key=lambda r: r['num'])
        shown = [r for r in rows if r['is_high'] or args.include_low]
        for r in shown:
            tag = '★HIGH' if r['is_high'] else 'low  '
            print(f"  {r['num']:3} {SCRY_RAR.get(r['rarity'].lower(), r['rarity']):4} {tag} {r['en_name'][:22]:22} #{r['number']} ({r['en_slug']})")
        nhigh = sum(1 for r in rows if r['is_high'])
        print(f"  → 누락 중 고레어 {nhigh} / 전체누락 {len(rows)}")
        all_rows += shown

    out = os.path.join(P, 'scrydex_set_gap_missing.csv')
    with open(out, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['jp_ref', 'num', 'en_slug', 'en_name', 'number', 'rarity', 'is_high', 'img', 'in_db'])
        w.writeheader(); w.writerows(all_rows)
    print(f"\n총 {len(all_rows)}행 → {out}")

if __name__ == '__main__':
    main()
