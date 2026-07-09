"""ADD 80장 → 기존 관리자 단건 카드추가(POST /api/admin/cards) payload 변환 (preview only, 호출 X).
 대상 = PRIMARY · jp_conf==JP_MATCH_EXACT · verdict==ADD.
 제외 = EXCLUDE_JP / DEFER_RR / NEEDS_TRAINER.
 productId = KO 세트명 → prod_products_snapshot 매칭(없으면 미해결로 표시, product 선생성 필요).
 DB/API write 0.
"""
import json, csv, os, re, collections

P = os.path.dirname(os.path.abspath(__file__))


def nset(s):
    return re.sub(r'[\s「」（）()【】]', '', (s or '')).lower()


# prod 세트명 → product_id (KO 언어 우선)
prod_products = []
with open(os.path.join(P, 'prod_products_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        prod_products.append(r)
by_name = {}
for r in prod_products:
    key = nset(r['name'])
    if r.get('language', 'KO') == 'KO' or key not in by_name:
        by_name[key] = r

data = json.load(open(os.path.join(P, 'jp_match_preview.json')))
target = [r for r in data if r.get('batch') == 'PRIMARY' and r.get('jp_conf') == 'JP_MATCH_EXACT' and r.get('verdict') == 'ADD']

payload, unmapped_sets, fails = [], collections.Counter(), []
for r in target:
    prod = by_name.get(nset(r['ko_set_name']))
    super_type = 'TRAINER' if '서포트' in (r.get('type') or '') else 'POKEMON'
    en_ref = r.get('en_ref') if r.get('en_conf') == 'EN_MATCH_EXACT' else None
    body = {
        'type': 'KO',
        'name': r['ko_name'],
        'productId': prod['product_id'] if prod else None,
        'rarityCode': r['ko_rarity'],
        'collectionNumber': r['ko_collection_no'],
        'superType': super_type,
        'subType': None,
        'officialCardCode': r['code'],
        'enScrydexRef': en_ref,
        'jpScrydexRef': r.get('jp_ref'),
        '_ko_set_name': r['ko_set_name'],
        '_ko_image_url': r['ko_image_url'],   # 참고용(백엔드 enrich는 jp ref로 이미지미러)
        '_ko_detail_url': r['ko_detail_url'],
    }
    if not r.get('jp_ref') or not r['code'] or not r['ko_name']:
        fails.append((r['code'], 'jp_ref/code/name 누락'))
        continue
    if not prod:
        unmapped_sets[r['ko_set_name']] += 1
    payload.append(body)

# 산출물
json.dump(payload, open(os.path.join(P, 'final_add_candidates_for_admin.json'), 'w'), ensure_ascii=False, indent=1)
cols = ['officialCardCode', 'name', 'rarityCode', 'collectionNumber', 'productId', '_ko_set_name', 'jpScrydexRef', 'enScrydexRef', 'superType', 'type']
with open(os.path.join(P, 'final_add_candidates_for_admin.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=cols)
    w.writeheader()
    for b in payload:
        w.writerow({k: b.get(k, '') for k in cols})

# ── dry-run 리포트 ──
all_prim = [r for r in data if r.get('batch') == 'PRIMARY']
print("=== 관리자 단건추가 payload 변환 (POST /api/admin/cards) — preview only ===\n")
print("[필드 매핑]")
print("  officialCardCode ← pokemoncard code(BS…)")
print("  name             ← ko_name")
print("  rarityCode       ← ko_rarity (pokemoncard 코드, admin 그대로 사용)")
print("  collectionNumber ← ko_collection_no")
print("  superType        ← type(서포트→TRAINER, else POKEMON)")
print("  jpScrydexRef     ← JP_MATCH_EXACT ref")
print("  enScrydexRef     ← EN_MATCH_EXACT ref, 아니면 null")
print("  productId        ← KO 세트명 → prod product 매칭")
print("  (이미지=백엔드 enrich가 jp ref로 S3 미러 / 시세=enrich가 fetch — _ko_image_url 은 참고용)")

print(f"\n[대상/제외 수]")
print(f"  PRIMARY 전체           {len(all_prim)}")
print(f"  변환 대상(ADD·JP EXACT) {len(target)}")
print(f"  EXCLUDE_JP 제외        {sum(1 for r in all_prim if r.get('verdict')=='EXCLUDE_JP')}")
print(f"  트레이너 보류 제외       {sum(1 for r in all_prim if r.get('needs_manual'))}")
print(f"  RR 보류(별탭) 제외      {sum(1 for r in data if r.get('batch')=='DEFER_RR')}")
print(f"  → payload 생성          {len(payload)}")

print(f"\n[누락/주의]")
print(f"  변환 실패(필드누락)     {len(fails)} {fails[:5]}")
en_cnt = sum(1 for b in payload if b['enScrydexRef'])
print(f"  enScrydexRef 채워짐     {en_cnt} / {len(payload)} (나머지 null=EN 수동매핑 대상)")
mapped = sum(1 for b in payload if b['productId'])
print(f"  productId 매핑됨        {mapped} / {len(payload)}")
print(f"  productId 미매핑 세트   {len(unmapped_sets)}종 (product 선생성 필요):")
for s, n in unmapped_sets.most_common():
    print(f"     {n:2}장  {s}")
print(f"\n산출물: final_add_candidates_for_admin.json / .csv")
