#!/usr/bin/env python3
"""나머지 45장 DB apply (--skip-images, 치라미 멱등skip) + make-visible. 이미지 이미 업로드됨. 스캐너 미변경."""
import json, collections, subprocess, os, re, tempfile

m = json.load(open('approved_46_final_manifest.json'))
byp = collections.defaultdict(list)
for x in m:
    byp[x['product_id']].append(x)
IMP = '/Users/fury/pokemon-card-app/python/catalog_import/import_card_set.py'
tmp = tempfile.mkdtemp()

def run(pid, payload_path, extra):
    return subprocess.run(['python3', IMP, '--input', payload_path, '--product-id', pid, '--apply'] + extra,
                          capture_output=True, text=True, timeout=300)

# 페이로드 미리 생성
pf = {}
for pid, cards in byp.items():
    payload = [{'jp_scrydex_ref': c['jp_ref'], 'name': c['ko_name'], 'rarity': c['rarity'],
                'collection_number': c['collection_no'], 'super_type': c['super_type'],
                'en_scrydex_ref': c['en_ref'] or 'NO_EN', 'card_id': c['card_id']} for c in cards]
    p = os.path.join(tmp, f'{pid}.json'); json.dump(payload, open(p, 'w'), ensure_ascii=False); pf[pid] = p

print(f"=== ① INSERT 45장 ({len(byp)} product, 치라미 skip) ===")
total_ins = total_skip = 0; fails = []
for pid, cards in byp.items():
    out = run(pid, pf[pid], ['--skip-images']).stdout
    ins = re.findall(r'INSERT 0 (\d+)', out)
    cardN = int(ins[0]) if ins else 0
    skip = len(re.findall(r'멱등 skip', out))
    commit = 'COMMIT' in out
    err = 'Traceback' in out or '검증오류' in out or 'ABORT' in out
    total_ins += cardN
    if '멱등 skip' in out: total_skip += 1
    if err or not commit: fails.append((pid, cards[0]['series'], out[-200:]))
    print(f"  {cards[0]['series']:12} insert {cardN} {'(치라미skip)' if 'sv5k' in pid[:4] or '멱등' in out else ''} {'COMMIT' if commit else 'NO-COMMIT'} {'❌' if (err or not commit) else '✓'}")
if fails:
    print(f"\n❌ INSERT 실패 {len(fails)} — make-visible 중단, 보고 후 정지")
    for pid, s, snip in fails[:5]: print(f"  {s}: {snip[:120]}")
    raise SystemExit(1)
print(f"  → 카드 insert 합계 {total_ins} (기대 45, 치라미는 skip)")

print(f"\n=== ② make-visible (46 전체) ===")
visN = 0
for pid, cards in byp.items():
    out = run(pid, pf[pid], ['--make-visible']).stdout
    u = re.findall(r'UPDATE (\d+)', out)
    visN += int(u[0]) if u else 0
print(f"  make-visible UPDATE 합계 {visN}")
print("\n  ✓ INSERT 45 + make-visible 완료. 다음=DB 46 전체검증 (별도).")
