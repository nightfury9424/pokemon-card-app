#!/usr/bin/env python3
"""게이트6: import_card_set가 manifest card_id를 그대로 사용하는지 증명 (dry-run, prod write 0).
dry-run 출력의 '[DRY] would upload ... jp/{card_id}.png'에서 실제 사용 card_id 추출 → manifest와 대조."""
import json, collections, subprocess, os, re, tempfile

m = json.load(open('approved_46_final_manifest.json'))
byp = collections.defaultdict(list)
for x in m:
    byp[x['product_id']].append(x)
manifest_cid = {x['jp_ref']: x['card_id'] for x in m}

IMP = '/Users/fury/pokemon-card-app/python/catalog_import/import_card_set.py'
tmp = tempfile.mkdtemp()
match = mismatch = 0
mismatches = []
print(f"=== 게이트6: card_id 흐름 검증 ({len(m)}장 / {len(byp)} product) ===\n")
for pid, cards in byp.items():
    payload = [{'jp_scrydex_ref': c['jp_ref'], 'name': c['ko_name'], 'rarity': c['rarity'],
                'collection_number': c['collection_no'], 'super_type': c['super_type'],
                'en_scrydex_ref': c['en_ref'] or 'NO_EN', 'card_id': c['card_id']} for c in cards]
    pf = os.path.join(tmp, f'{pid}.json')
    json.dump(payload, open(pf, 'w'), ensure_ascii=False)
    p = subprocess.run(['python3', IMP, '--input', pf, '--product-id', pid], capture_output=True, text=True, timeout=300)
    out = p.stdout + p.stderr
    # [DRY] would upload {scrydex ref} → s3://.../jp/{card_id}.png
    up = dict(re.findall(r'would upload https://images\.scrydex\.com/pokemon/([a-z0-9_]+-\d+)/medium .*?/jp/(CRD_[0-9A-F]+)\.png', out))
    for c in cards:
        used = up.get(c['jp_ref'])
        if used == c['card_id']:
            match += 1
        else:
            mismatch += 1
            mismatches.append((c['jp_ref'], c['card_id'], used))

print(f"  manifest card_id == dry-run 사용 card_id : {match}/{len(m)}")
print(f"  불일치: {mismatch}")
if mismatches:
    for jp, want, got in mismatches[:10]:
        print(f"    ✗ {jp}: manifest={want} dryrun={got}")
print(f"\n  >>> {'PASS — importer가 manifest card_id 그대로 사용 ✅' if mismatch == 0 else 'FAIL'} <<<")
