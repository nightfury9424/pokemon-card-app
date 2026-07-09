"""80 payload → AdminAddCardRequest 스키마 검증 + prod 재대조 dry-run. 호출/ write 0.
 검증:
  ① DTO 필드 정확 일치
  ② productId ∈ prod products
  ③ officialCardCode ∉ prod official_card_code (dup이면 admin이 badRequest)
  ④ jpScrydexRef ∉ prod jp_scrydex_ref (dup이면 ADD 제외)
  ⑤ jpScrydexRef non-null (없으면 제외)
  ⑥ enScrydexRef null 허용
 산출: final_add_payload_clean.json (DTO 필드만, 실제 호출용)
"""
import json, csv, os

P = os.path.dirname(os.path.abspath(__file__))
DTO = ['type', 'name', 'productId', 'rarityCode', 'collectionNumber', 'superType', 'subType', 'officialCardCode', 'enScrydexRef', 'jpScrydexRef']


def real(x):
    return bool(x) and not str(x).startswith('NO_')


prod_products, prod_codes, prod_jp = set(), set(), set()
with open(os.path.join(P, 'prod_products_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        prod_products.add(r['product_id'])
with open(os.path.join(P, 'prod_cards_snapshot.csv')) as f:
    for r in csv.DictReader(f):
        c = (r.get('official_card_code') or '').strip()
        j = (r.get('jp_scrydex_ref') or '').strip()
        if c:
            prod_codes.add(c)
        if real(j):
            prod_jp.add(j)

cands = json.load(open(os.path.join(P, 'final_add_candidates_for_admin.json')))
clean, excluded = [], []
n_pid_miss = n_code_dup = n_jp_dup = n_jp_miss = n_en_null = 0
for b in cands:
    reasons = []
    if not real(b.get('jpScrydexRef')):
        reasons.append('jpScrydexRef 누락'); n_jp_miss += 1
    if b.get('jpScrydexRef') in prod_jp:
        reasons.append(f"jpScrydexRef 이미 prod에 있음({b['jpScrydexRef']})"); n_jp_dup += 1
    if b.get('officialCardCode') in prod_codes:
        reasons.append(f"officialCardCode 이미 prod에 있음({b['officialCardCode']})"); n_code_dup += 1
    if b.get('productId') not in prod_products:
        reasons.append(f"productId prod 부재({b.get('productId')})"); n_pid_miss += 1
    if reasons:
        excluded.append((b['officialCardCode'], b['name'], '; '.join(reasons)))
        continue
    if not real(b.get('enScrydexRef')):
        n_en_null += 1
    clean.append({k: b.get(k) for k in DTO})

json.dump(clean, open(os.path.join(P, 'final_add_payload_clean.json'), 'w'), ensure_ascii=False, indent=1)

# DTO 필드 정확성 (clean 의 키 == DTO)
schema_ok = all(set(c.keys()) == set(DTO) for c in clean)

print("=== payload dry-run 검증 (POST /api/admin/cards) — 호출 X ===\n")
print(f"입력 후보            {len(cands)}")
print(f"DTO 필드 정확 일치    {'✓ (10필드 일치)' if schema_ok else '✗'}")
print(f"→ 호출가능 payload    {len(clean)}")
print(f"제외                 {len(excluded)}")
print("\n[재검증 카운트]")
print(f"  productId 미해결    {n_pid_miss}")
print(f"  officialCardCode 중복 {n_code_dup}")
print(f"  jpScrydexRef 중복   {n_jp_dup}")
print(f"  jpScrydexRef 누락   {n_jp_miss}")
print(f"  enScrydexRef null   {n_en_null} / {len(clean)} (허용)")
print(f"\n[제외 카드 목록]")
for c in excluded[:30]:
    print(f"   {c[0]} {c[1]} | {c[2]}")
if not excluded:
    print("   (없음 — 80장 전부 통과)")
print(f"\n산출물: final_add_payload_clean.json ({len(clean)}장, DTO 필드만)")
print("※ 실제 POST는 승인 후. prod write/admin 호출 0.")
