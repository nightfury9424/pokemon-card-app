#!/usr/bin/env python3
"""approved_49 이미지 URL 전수검증 (read-only). HTTP/content-type/size/decode/dim + 교차언어 일러스트."""
import json, csv, io, urllib.request
from PIL import Image

UA = "Mozilla/5.0 AppleWebKit/537.36 Chrome/120"
m = json.load(open('approved_49_final_manifest.json'))
sims = json.load(open('/tmp/crosslang_sims.json'))

def probe(url):
    if not url: return dict(status='N/A', ct='', size=0, w=0, h=0, decode='N/A')
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        r = urllib.request.urlopen(req, timeout=25)
        data = r.read()
        ct = r.headers.get('Content-Type', '')
        try:
            im = Image.open(io.BytesIO(data)); im.load(); w, h = im.size; dec = 'OK'
        except Exception as e:
            w = h = 0; dec = 'FAIL:' + str(e)[:20]
        return dict(status=r.status, ct=ct, size=len(data), w=w, h=h, decode=dec)
    except Exception as e:
        return dict(status='ERR:' + str(e)[:20], ct='', size=0, w=0, h=0, decode='ERR')

rows = []
for x in m:
    code = x['code']; sm = sims.get(code, {})
    ko = probe(x['ko_img']); jp = probe(x['jp_img'])
    has_en = bool(x['en_ref'])
    en = probe(x['en_img']) if has_en else dict(status='N/A', ct='', size=0, w=0, h=0, decode='N/A')
    kojp = sm.get('ko_jp'); koen = sm.get('ko_en'); jpen = sm.get('jp_en')
    # 이미지 기술 PASS: KO·JP 200+decode + (EN 있으면 200+decode)
    def good(p): return (p['status'] == 200) and p['decode'] == 'OK' and p['size'] > 0 and ('image' in p['ct'])
    tech_ok = good(ko) and good(jp) and (good(en) if has_en else True)
    # 교차언어 동일 일러스트: KO↔JP ≥0.80 (0.75~0.80 BORDERLINE, <0.75 DIFF)
    xl = 'OK' if (kojp is not None and kojp >= 0.80) else ('BORDERLINE' if (kojp is not None and kojp >= 0.75) else 'DIFF/NA')
    if has_en and koen is not None and koen < 0.75 and xl == 'OK':
        xl = 'EN_DIFF'
    pf = 'PASS' if (tech_ok and xl in ('OK', 'BORDERLINE')) else 'FAIL'
    rows.append(dict(code=code, ko_name=x['ko_name'], jp_ref=x['jp_ref'], en_ref=x['en_ref'],
                     ko_url=x['ko_img'], jp_url=x['jp_img'], en_url=x['en_img'],
                     ko_status=ko['status'], jp_status=jp['status'], en_status=en['status'],
                     ko_ct=ko['ct'], jp_ct=jp['ct'], en_ct=en['ct'],
                     ko_size=ko['size'], jp_size=jp['size'], en_size=en['size'],
                     ko_dim=f"{ko['w']}x{ko['h']}", jp_dim=f"{jp['w']}x{jp['h']}", en_dim=f"{en['w']}x{en['h']}",
                     ko_decode=ko['decode'], jp_decode=jp['decode'], en_decode=en['decode'],
                     ko_jp=kojp, ko_en=koen, jp_en=jpen, crosslang=xl, result=pf))

with open('approved_49_image_audit.csv', 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)

# 요약
ko200 = sum(1 for r in rows if r['ko_status'] == 200)
jp200 = sum(1 for r in rows if r['jp_status'] == 200)
en_need = [r for r in rows if r['en_ref']]
en200 = sum(1 for r in en_need if r['en_status'] == 200)
kod = sum(1 for r in rows if r['ko_decode'] == 'OK')
jpd = sum(1 for r in rows if r['jp_decode'] == 'OK')
print(f"=== 이미지 전수검증 (49장) ===")
print(f"  KO HTTP 200: {ko200}/49 · decode OK: {kod}/49")
print(f"  JP HTTP 200: {jp200}/49 · decode OK: {jpd}/49")
print(f"  EN(en_ref {len(en_need)}장) HTTP 200: {en200}/{len(en_need)}")
import collections
print(f"  교차언어 일러스트: {dict(collections.Counter(r['crosslang'] for r in rows))}")
fails = [r for r in rows if r['result'] == 'FAIL']
print(f"  PASS {sum(1 for r in rows if r['result']=='PASS')}/49 · FAIL {len(fails)}")
for r in fails:
    print(f"    FAIL {r['ko_name']}({r['jp_ref']}): ko={r['ko_status']}/{r['ko_decode']} jp={r['jp_status']}/{r['jp_decode']} en={r['en_status']} xl={r['crosslang']} ko_jp={r['ko_jp']}")
bd = [r for r in rows if r['crosslang'] == 'BORDERLINE']
if bd: print(f"  BORDERLINE(사용자 육안 확인필요): {[(r['ko_name'],r['ko_jp']) for r in bd]}")
print(f"\n  → approved_49_image_audit.csv ({len(rows)}행)")
