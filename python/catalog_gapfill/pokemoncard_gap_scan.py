"""pokemoncard.co.kr 세트별 갭 스캔 — 누락 고레어(RR+) 탐지 (2026-06-20 검증된 메소드).

검증 사실(실측):
  - detail 페이지 = 서버사이드 렌더(jQuery, SPA 아님). URL=`/cards/detail/{CODE}` 예 BS2026002095.
  - 존재 판별 = 응답 본문 길이 신호: len>15000 = 카드 존재 / len~11356 = 빈 템플릿(없음).
  - 레어도 = `<span id="no_wrap_by_admin"> RR </span>` 텍스트. ★단 742-base 대형세트 시크릿은
    레어도가 아이콘 이미지라 텍스트 '?' → base 초과 번호 + 이름(ex)로 chase 판정.
  - 번호 = `NNN/MMM` (MMM=base 세트크기). 번호>base = 시크릿(SR/SAR/AR/MUR 등 chase).
  - 이름 = `class="...tit..."` 요소.

갭 모델(검증):
  ★ "base 위 ±N 스캔"이 정답인 세트 多 (BS2026002: base80, 081-105에 AR/SR chase).
  ★ 단 일부 세트는 base 위 chase 0 (BS2026003: 83장 끝). 세트마다 다름 → 세트당 full 스캔.
  ★ 우리가 0장 보유한 세트코드는 ±100으로 못 찾음 → 세트코드 공간 discovery 별도 필요.

사용:
  python pokemoncard_gap_scan.py --sets BS2026001 BS2026002        # 특정 세트
  python pokemoncard_gap_scan.py --discover 2026                    # BS2026001..050 코드 존재 발견
  python pokemoncard_gap_scan.py --all-held                         # prod 보유 전 세트코드 스캔(대량)

출력: pokemoncard_gap_missing.csv (코드,번호,추정레어,이름,base,is_secret,이미지URL)
DB/POST write 0. 정중: 요청간 딜레이, 연속 empty 8개면 세트 종료.
"""
import csv, re, os, sys, time, argparse, collections, urllib.request

P = os.path.dirname(os.path.abspath(__file__))
UA = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'}
HIGH = {'RR','SR','SAR','AR','HR','UR','MUR','SSR','CHR','CSR','RRR','S','K'}
DELAY = 0.4

def load_holdings():
    """prod_cards_snapshot -> {setcode9: {num:(name,rarity)}}"""
    hold = collections.defaultdict(dict)
    path = os.path.join(P, 'prod_cards_snapshot.csv')
    for r in csv.DictReader(open(path)):
        c = r['official_card_code'].strip()
        if len(c) >= 9:
            m = re.match(r'(\d+)', r['collection_number'])
            if m:
                hold[c[:9]][int(m.group(1))] = (r['name'], r['rarity_code'])
    return hold

def fetch(code):
    try:
        req = urllib.request.Request(f"https://pokemoncard.co.kr/cards/detail/{code}", headers=UA)
        b = urllib.request.urlopen(req, timeout=12).read().decode('utf-8', 'replace')
        return b if len(b) > 15000 else None
    except Exception:
        return None

def parse(b):
    rar = re.search(r'id="no_wrap_by_admin">\s*([A-Z]{1,4})\s*<', b)
    num = re.search(r'\b(\d{1,3}/\d{1,3})\b', b)
    nm = re.search(r'class="[^"]*tit[^"]*"[^>]*>([^<]{1,30})', b)
    img = re.search(r'(https://cards\.image\.pokemonkorea\.co\.kr/[^"\')\s]+\.png)', b)
    base = int(num.group(1).split('/')[1]) if num else None
    n = int(num.group(1).split('/')[0]) if num else None
    return dict(rar=rar.group(1) if rar else '?',
                num=n, base=base,
                name=(nm.group(1).strip() if nm else '?'),
                img=(img.group(1) if img else ''))

def scan_set(code9, hold, maxn=130):
    """세트 full 스캔: 001..maxn, 연속 empty 8개면 중단. 누락 고레어만 반환."""
    held = hold.get(code9, {})
    miss, empties = [], 0
    for n in range(1, maxn + 1):
        b = fetch(f"{code9}{n:03d}")
        if not b:
            empties += 1
            if empties >= 8 and n > 1:
                break
            time.sleep(DELAY)
            continue
        empties = 0
        p = parse(b)
        is_secret = bool(p['base'] and p['num'] and p['num'] > p['base'])
        # chase 판정: 텍스트 레어 HIGH 이거나, 시크릿 번호이거나, 이름에 ex/V
        is_chase = (p['rar'] in HIGH) or is_secret or (' ex' in p['name'] or p['name'].endswith('V'))
        if is_chase and n not in held:
            row = dict(code=code9, num=f"{n:03d}", rar=p['rar'], name=p['name'],
                       base=p['base'], is_secret=is_secret, img=p['img'])
            miss.append(row)
            print(f"  ❌누락 {code9}{n:03d} {p['rar']:4} {'SECRET' if is_secret else 'base':6} {p['name']}")
        time.sleep(DELAY)
    return miss

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--sets', nargs='*', help='세트코드9 직접 지정')
    ap.add_argument('--discover', help='연도(예 2026): BS{year}001..050 존재 발견')
    ap.add_argument('--all-held', action='store_true', help='prod 보유 전 세트코드')
    ap.add_argument('--maxn', type=int, default=130)
    args = ap.parse_args()
    hold = load_holdings()

    if args.discover:
        y = args.discover
        print(f"=== BS{y}001..050 세트코드 존재 발견 ===")
        for s in range(1, 51):
            code = f"BS{y}{s:03d}"
            b = fetch(code + "001")
            if b:
                p = parse(b)
                held = len(hold.get(code, {}))
                print(f"  {code}  base={p['base']}  보유 {held}장  (001={p['name']})")
            time.sleep(DELAY)
        return

    if args.sets:
        targets = args.sets
    elif args.all_held:
        targets = sorted(k for k in hold if k.startswith('BS'))
        print(f"=== 보유 세트 {len(targets)}개 전체 스캔 ===")
    else:
        print("--sets / --discover / --all-held 중 하나 지정"); return

    all_miss = []
    for code in targets:
        print(f"\n=== {code} 스캔 (보유 {len(hold.get(code,{}))}장) ===")
        all_miss += scan_set(code, hold, args.maxn)

    out = os.path.join(P, 'pokemoncard_gap_missing.csv')
    with open(out, 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=['code','num','rar','name','base','is_secret','img'])
        w.writeheader()
        w.writerows(all_miss)
    print(f"\n총 누락 고레어 {len(all_miss)}장 → {out}")

if __name__ == '__main__':
    main()
