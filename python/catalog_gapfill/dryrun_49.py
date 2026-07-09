#!/usr/bin/env python3
"""approved_49 manifest → product별 import_card_set.py DB dry-run (BEGIN→verify→ROLLBACK). prod write 0."""
import json, collections, subprocess, os, re, tempfile

m = json.load(open('approved_49_final_manifest.json'))
byp = collections.defaultdict(list)
for x in m:
    byp[x['product_id']].append(x)

IMP = '/Users/fury/pokemon-card-app/python/catalog_import/import_card_set.py'
tmp = tempfile.mkdtemp()
results = []
total_cards = total_jp = total_ko = 0
checksum_before = checksum_after = None

print(f"=== 49장 DB dry-run · {len(byp)} product ===\n")
for pid, cards in byp.items():
    payload = [{
        'jp_scrydex_ref': c['jp_ref'], 'name': c['ko_name'], 'rarity': c['rarity'],
        'collection_number': c['collection_no'], 'super_type': c['super_type'],
        'en_scrydex_ref': c['en_ref'] or 'NO_EN',
    } for c in cards]
    pf = os.path.join(tmp, f'{pid}.json')
    json.dump(payload, open(pf, 'w'), ensure_ascii=False)
    p = subprocess.run(['python3', IMP, '--input', pf, '--product-id', pid],
                       capture_output=True, text=True, timeout=300)
    out = p.stdout + p.stderr
    ins = re.findall(r'INSERT 0 (\d+)', out)
    cardN = int(ins[0]) if len(ins) >= 1 else 0
    jpN = int(ins[1]) if len(ins) >= 2 else 0
    koN = int(ins[2]) if len(ins) >= 3 else 0
    commit = 'COMMIT' in out
    rollback = 'ROLLBACK' in out
    err = ('오류' in out and 'ABORT' in out) or 'Traceback' in out or '미지원' in out or 'ERROR' in out
    cks = re.findall(r'^\s*(\d{6,})\s*\|\s*(\d+)', out, re.M)
    series = cards[0]['series']
    ok = (cardN == len(cards)) and rollback and not commit and not err
    results.append({'pid': pid, 'series': series, 'expect': len(cards), 'card': cardN, 'jp': jpN, 'ko': koN,
                    'rollback': rollback, 'commit': commit, 'err': err, 'ok': ok,
                    'errsnip': '' if not err else next((l for l in out.splitlines() if ('미지원' in l or 'ABORT' in l or 'Error' in l)), '')[:80]})
    total_cards += cardN; total_jp += jpN; total_ko += koN
    print(f"  {series:12} {pid[:18]} 기대{len(cards)} → insert {cardN} (jp {jpN}, ko {koN}) {'ROLLBACK' if rollback else ''} {'✅' if ok else '❌ '+results[-1]['errsnip']}")

okN = sum(1 for r in results if r['ok'])
print(f"\n=== 집계 ===")
print(f"  product {len(byp)} · dry-run PASS {okN}/{len(byp)}")
print(f"  카드 insert(dry) 합계 {total_cards} (기대 49) · SCRYDEX_JP {total_jp} · KO_ESTIMATED {total_ko}")
print(f"  COMMIT 발생: {sum(1 for r in results if r['commit'])} (0이어야 — 전부 ROLLBACK)")
print(f"  에러 product: {[r['series'] for r in results if r['err']]}")
fails = [r for r in results if not r['ok']]
if fails:
    print(f"  ❌ FAIL {len(fails)}: " + ', '.join(f"{r['series']}({r['errsnip']})" for r in fails))
else:
    print(f"  >>> 49장 DB dry-run 전부 PASS — 카드/백필 insert 검증, 전부 ROLLBACK, 에러 0 <<<")
json.dump(results, open('/tmp/dryrun_49_results.json', 'w'), ensure_ascii=False, indent=1)
