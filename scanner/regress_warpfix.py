#!/usr/bin/env python3
"""warp-fix 회귀 하네스. /identify(운영경로) POST로 실스캔+신규46+탱탱겔 Top-1 측정.
용법: python regress_warpfix.py <baseline|fixed>"""
import sys, json, os, glob, random, time, urllib.request, collections

TAG = sys.argv[1] if len(sys.argv) > 1 else 'run'
meta = json.load(open('db/card_meta.json'))
idx = set(meta['cards'])
m = json.load(open('/Users/fury/pokemon-card-app/python/catalog_gapfill/approved_46_final_manifest.json'))
DST = 'data/cards'
random.seed(42)

items = []  # (path, expected_cid, source)
# 1) scan_captures (유저 실폰스캔) — 인덱스에 있는 카드만
for d in os.listdir('data/scan_captures'):
    if d not in idx: continue
    caps = glob.glob(f'data/scan_captures/{d}/*.jpg')
    for c in caps: items.append((c, d, 'scan_capture'))
# 2) realshots (실사진) — 카드당 1장 샘플, 인덱스 카드만
rs = [d for d in os.listdir('data/realshots') if d in idx]
for d in rs:  # ★전체 566(인덱스 카드), 카드당 1장
    fs = sorted(glob.glob(f'data/realshots/{d}/*.jpg'))
    if fs: items.append((fs[0], d, 'realshot'))
# 3) 신규 46 KO/JP/EN
for x in m:
    cid = x['card_id']
    for sfx, src in [('_ko', 'new_ko'), ('_jp', 'new_jp'), ('_en', 'new_en')]:
        p = f'{DST}/{cid}{sfx}.png'
        if not os.path.exists(p) and sfx == '_ko':
            p = f'{DST}/{cid}{sfx}.png.bad_warp'  # 탱탱겔
        if os.path.exists(p): items.append((p, cid, src))

print(f"[{TAG}] 테스트 항목 {len(items)} (scan_capture/realshot/new_ko/jp/en)")

def identify(path):
    t0 = time.time()
    try:
        with open(path, 'rb') as f:
            body = f.read()
        boundary = '----b'
        data = (f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="x.png"\r\n'
                f'Content-Type: image/png\r\n\r\n').encode() + body + f'\r\n--{boundary}--\r\n'.encode()
        req = urllib.request.Request('http://localhost:8082/identify', data=data,
                                     headers={'Content-Type': f'multipart/form-data; boundary={boundary}'})
        d = json.load(urllib.request.urlopen(req, timeout=30))
        dd = d.get('data', {}) or {}
        cs = dd.get('candidates', [])
        t1 = cs[0] if cs else {}
        t2s = cs[1]['score'] if len(cs) > 1 else 0
        return t1.get('cardId'), round(t1.get('score', 0), 3), round(t1.get('score', 0) - t2s, 3), round(time.time() - t0, 3)
    except Exception as e:
        return 'ERR', 0, 0, round(time.time() - t0, 3)

res = []
bysrc = collections.defaultdict(lambda: [0, 0])
for i, (p, exp, src) in enumerate(items):
    pred, sc, mg, dt = identify(p)
    ok = (pred == exp)
    bysrc[src][0] += ok; bysrc[src][1] += 1
    res.append({'path': p, 'expected': exp, 'pred': pred, 'score': sc, 'margin': mg, 'time': dt, 'src': src, 'ok': ok})
    if (i + 1) % 100 == 0: print(f"  ...{i+1}/{len(items)}")

json.dump(res, open(f'/tmp/regress_{TAG}.json', 'w'))
print(f"\n[{TAG}] 소스별 Top-1 정확도:")
for s, v in sorted(bysrc.items()):
    print(f"  {s}: {v[0]}/{v[1]} ({100*v[0]//max(v[1],1)}%)")
times = [r['time'] for r in res]
print(f"  평균 처리시간 {sum(times)/len(times):.3f}s · 최대 {max(times):.3f}s")
# 탱탱겔 KO
tg = [r for r in res if r['expected'] == 'CRD_A52ADAD23735C0E3C95C' and r['src'] == 'new_ko']
if tg: print(f"  ★탱탱겔 KO: pred={tg[0]['pred'][:14] if tg[0]['pred'] else None} score={tg[0]['score']} {'PASS' if tg[0]['ok'] else 'FAIL'}")
