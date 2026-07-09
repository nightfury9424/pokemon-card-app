"""PRICE_MODEL_V8 (JP-sanity-first) dry-run — 설계 검증용. 코드/prod/write 0.
 단일 anchor decision 함수를 기존 3,741장(6/18 prod) + 신규 59장에 동일 적용.
 입력(read-only): jp_first_policy_audit_20260619/ 의 prod 덤프 + anchor_audit_20260619/ 의 59 raw·manual.
 출력: ~/Downloads/price_v8_design_20260619/ 의 CSV/MD.
"""
import csv, json, os, re, collections, statistics

HOME = os.path.expanduser("~")
IN = "/tmp/jf_inputs"
AA = "/tmp/anchor_audit_20260619"
OUT = "/tmp/price_v8_design_20260619"
os.makedirs(OUT, exist_ok=True)
GRAIL = 300000   # 고가 임계(원): no-ladder인데 이 이상이면 MANUAL_REVIEW


def num(x):
    try:
        return float(x)
    except Exception:
        return None


# manual anchor / floor / frozen (prod v6)
mtxt = open(f"{AA}/data/prod_v6_manual_anchor.txt").read()
_mf = f"{IN}/prod_manual_anchor_floor.txt"
if os.path.exists(_mf):
    mtxt += open(_mf).read()
MANUAL_ANCHOR = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':\((\d+),", mtxt)}
MANUAL_FLOOR = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':(\d+),?\s*#", mtxt)}

# price pivot (6/18): jp_raw, jp_psa10/9, en_raw, en_psa10/9
P = collections.defaultdict(dict)
for r in csv.DictReader(open(f"{IN}/prod_jp_en_raw_graded_0618.csv")):
    p = num(r['price'])
    if p is None:
        continue
    lang = 'jp' if r['source'] == 'SCRYDEX_JP' else 'en'
    key = f"{lang}_raw" if r['card_status'] == 'RAW' else f"{lang}_psa{r['grade_value']}"
    P[r['card_id']][key] = p

# audit 6/18 + coef 추정
AU = {r['card_id']: r for r in csv.DictReader(open(f"{IN}/prod_ko_estimated_audit_20260608_20260618.csv")) if r['estimated_date'] == '2026-06-18'}
rar_jpc = collections.defaultdict(list); rar_enc = collections.defaultdict(list); card_jpc = {}
for r in csv.DictReader(open(f"{IN}/prod_ko_estimated_audit_20260608_20260618.csv")):
    ko = num(r['ko_price']); raw = num(r['selected_raw_price_krw'])
    if ko and raw and raw > 0:
        if r['selected_source'] == 'JP':
            rar_jpc[r['rarity_code']].append(ko / raw); card_jpc[r['card_id']] = ko / raw
        elif r['selected_source'] == 'EN':
            rar_enc[r['rarity_code']].append(ko / raw)
ALLJ = [v for L in rar_jpc.values() for v in L]; ALLE = [v for L in rar_enc.values() for v in L]


def jpc(cid, rar):
    return card_jpc.get(cid) or (statistics.median(rar_jpc[rar]) if rar_jpc.get(rar) else (statistics.median(ALLJ) if ALLJ else 0.16))


def enc(rar):
    return statistics.median(rar_enc[rar]) if rar_enc.get(rar) else (statistics.median(ALLE) if ALLE else 0.34)


def vref(x):
    return bool(x) and not str(x).startswith('NO_')


def v8_decide(cid, rar, jpref, enref, jpraw, jp10, jp9, enraw, en10, en9, name=''):
    """returns (bucket, anchor, estimated, reason)."""
    ma = MANUAL_ANCHOR.get(cid); mf = MANUAL_FLOOR.get(cid)
    if ma is not None:
        return 'MANUAL_ANCHOR', 'MANUAL', int(ma), 'manual anchor 확정값'
    ladder = jp10 is not None or jp9 is not None
    if not vref(jpref) or jpraw is None:
        est = round(enraw * enc(rar)) if enraw else None
        return 'EN_FALLBACK_OK', 'EN', est, 'JP raw/ref 없음 → EN'
    if jp10 is not None and jpraw > jp10:
        return 'JP_SUSPECT', 'NONE', None, f'RAW>PSA10 (raw {int(jpraw)}>psa10 {int(jp10)}) → 자동금지'
    if jp9 is not None and jpraw > jp9:
        return 'JP_SUSPECT', 'NONE', None, f'RAW>PSA9 (raw {int(jpraw)}>psa9 {int(jp9)}) → 자동금지'
    if not ladder:
        if jpraw > GRAIL:
            return 'MANUAL_REVIEW', 'NONE', None, f'JP ladder 없음 + 고가({int(jpraw)}) → 검수'
        est = round(jpraw * jpc(cid, rar))
        return 'JP_VALID', 'JP', est, 'JP raw 저가·ladder없음 저위험 → JP'
    est = round(jpraw * jpc(cid, rar))
    if mf is not None and est < mf:
        return 'MANUAL_FLOOR', 'JP+FLOOR', int(mf), f'JP {est} < floor {int(mf)}'
    return 'JP_VALID', 'JP', est, 'raw<=psa9<=psa10 → JP'


COLS = ['card_id', 'name', 'rarity_code', 'product_id', 'official_card_code', 'jp_ref', 'en_ref',
        'current_anchor', 'current_ko_estimated', 'v8_bucket', 'v8_anchor', 'v8_estimated', 'diff', 'diff_pct',
        'jp_raw', 'jp_psa9', 'jp_psa10', 'en_raw', 'en_psa9', 'en_psa10', 'manual_anchor', 'manual_floor', 'reason']

rows = []
for cid, a in AU.items():
    pr = P.get(cid, {})
    jpraw, jp10, jp9 = pr.get('jp_raw'), pr.get('jp_psa10'), pr.get('jp_psa9')
    enraw, en10, en9 = pr.get('en_raw'), pr.get('en_psa10'), pr.get('en_psa9')
    b, anc, est, reason = v8_decide(cid, a['rarity_code'], a['jp_scrydex_ref'], a['en_scrydex_ref'], jpraw, jp10, jp9, enraw, en10, en9, a['name'])
    cur = num(a['ko_price'])
    diff = (est - cur) if (est is not None and cur is not None) else None
    rows.append({'card_id': cid, 'name': a['name'], 'rarity_code': a['rarity_code'], 'product_id': a['product_id'],
                 'official_card_code': a['official_card_code'], 'jp_ref': a['jp_scrydex_ref'], 'en_ref': a['en_scrydex_ref'],
                 'current_anchor': a['selected_source'], 'current_ko_estimated': int(cur) if cur else None,
                 'v8_bucket': b, 'v8_anchor': anc, 'v8_estimated': est, 'diff': int(diff) if diff is not None else None,
                 'diff_pct': round(100 * diff / cur, 1) if (diff is not None and cur) else None,
                 'jp_raw': int(jpraw) if jpraw else None, 'jp_psa9': int(jp9) if jp9 else None, 'jp_psa10': int(jp10) if jp10 else None,
                 'en_raw': int(enraw) if enraw else None, 'en_psa9': int(en9) if en9 else None, 'en_psa10': int(en10) if en10 else None,
                 'manual_anchor': int(MANUAL_ANCHOR[cid]) if cid in MANUAL_ANCHOR else None,
                 'manual_floor': int(MANUAL_FLOOR[cid]) if cid in MANUAL_FLOOR else None, 'reason': reason})


def dump(fn, data, cols=COLS):
    with open(f"{OUT}/{fn}", 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(data)


dump('v8_anchor_bucket_0618.csv', rows)
dump('v8_vs_current_0618.csv', [r for r in rows if r['v8_anchor'] != r['current_anchor'] or r['diff']])
dump('v8_manual_review_queue.csv', [r for r in rows if r['v8_bucket'] == 'MANUAL_REVIEW'])
dump('v8_jp_suspect_queue.csv', [r for r in rows if r['v8_bucket'] == 'JP_SUSPECT'])

# 신규 59
n59 = json.load(open(f"{AA}/data/anchor_preview_59_raw.json"))
n59rows = []
for c in n59:
    jpraw = c.get('jpRawKrw'); enraw = c.get('enRawKrw'); rar = c['ko_rarity']
    # 신규카드는 PSA ladder 없음(graded 미수집)
    b, anc, est, reason = v8_decide('NEW_' + c['code'], rar, c.get('jpScrydexRef'), c.get('enScrydexRef'), jpraw, None, None, enraw, None, None, c['ko_name'])
    n59rows.append({'card_id': 'NEW', 'name': c['ko_name'], 'rarity_code': rar, 'product_id': c.get('productId'),
                    'official_card_code': c['code'], 'jp_ref': c.get('jpScrydexRef'), 'en_ref': c.get('enScrydexRef'),
                    'current_anchor': c['anchorSource'].replace('SCRYDEX_', ''), 'current_ko_estimated': c['koEstimated'],
                    'v8_bucket': b, 'v8_anchor': anc, 'v8_estimated': est, 'diff': (est - c['koEstimated']) if est else None,
                    'diff_pct': round(100 * (est - c['koEstimated']) / c['koEstimated'], 1) if est else None,
                    'jp_raw': jpraw, 'jp_psa9': None, 'jp_psa10': None, 'en_raw': enraw, 'en_psa9': None, 'en_psa10': None,
                    'manual_anchor': None, 'manual_floor': None, 'reason': reason})
dump('v8_new_59_preview_compare.csv', n59rows)

bc = collections.Counter(r['v8_bucket'] for r in rows)
nbc = collections.Counter(r['v8_bucket'] for r in n59rows)
flipEJ = [r for r in rows if r['current_anchor'] == 'EN' and r['v8_anchor'] == 'JP']
summary = f"""# v8 dry-run 영향 요약 (6/18 prod {len(rows)}장 + 신규 59)

## 기존 3,741장 v8 버킷
{chr(10).join(f'- {k}: {v}' for k,v in bc.most_common())}

## 현재 vs v8 변화
- 현재 EN앵커 → v8 JP 교정: **{len(flipEJ)}장** (broad EN-over-selection 중 JP가 맞는 것)
- v8 자동가격 미산정(JP_SUSPECT+MANUAL_REVIEW): **{bc['JP_SUSPECT']+bc['MANUAL_REVIEW']}장** (검수중/기존유지)

## 신규 59장 v8 (PSA ladder 없음=신규)
{chr(10).join(f'- {k}: {v}' for k,v in nbc.most_common())}
- 대부분 저가라 JP_VALID(JP anchor)로 EN인플레 교정. 고가/grail만 MANUAL_REVIEW.

## 릴리에 검증
"""
lil = [r for r in rows if r['name'] == '릴리에']
for r in lil:
    summary += f"- {r['official_card_code']} jp_raw {r['jp_raw']} ladder=없음 → **{r['v8_bucket']}** (현재 {r['current_anchor']} {r['current_ko_estimated']}) — 자동가격 {r['v8_estimated']}\n"
summary += "\n## 상태\n코드/prod/sync/apply/admin-add 0. v8은 dry-run 설계만. v6 live run(23:45) 무관.\n"
open(f"{OUT}/v8_impact_summary.md", 'w').write(summary)

print(f"기존 v8 버킷: {dict(bc)}")
print(f"EN→JP 교정 {len(flipEJ)} | 미산정(suspect+review) {bc['JP_SUSPECT']+bc['MANUAL_REVIEW']}")
print(f"신규 59 v8: {dict(nbc)}")
print(f"릴리에: {[(r['v8_bucket'],r['v8_estimated']) for r in lil]}")
print(f"manual_anchor parsed {len(MANUAL_ANCHOR)} / manual_floor {len(MANUAL_FLOOR)}")
print(f"→ 산출물: {OUT}/")
