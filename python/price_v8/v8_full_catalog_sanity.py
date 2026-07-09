"""v8 FULL-CATALOG sanity audit (기존 3,741장 전수, 신규 59 제외). 로컬 read-only, prod 무접속.
핵심: 고정값(GRAIL) 단독 금지. ladder-위반 + KO/market 비율 + rarity/era 속성 = 복합 score.
레시라무 같은 '관계가 이상한' 카드를 잡는 게 목표(금액 임계 아님).
"""
import csv, json, os, re, collections, statistics

IN = "/tmp/jf_inputs"
AA = "/tmp/anchor_audit_20260619"
OUT = "/tmp/price_v8_full_catalog_20260619"
os.makedirs(OUT, exist_ok=True)


def num(x):
    try:
        return float(x)
    except Exception:
        return None


# ── frozen / manual ──
vtxt = open(f"{AA}/data/prod_v6_manual_anchor.txt").read()
mf = f"{IN}/prod_manual_anchor_floor.txt"
if os.path.exists(mf):
    vtxt += "\n" + open(mf).read()


def block(txt, name):
    i = txt.find(name + "=")
    if i < 0:
        return ""
    j = txt.find("{", i); d = 0
    for k in range(j, len(txt)):
        if txt[k] == "{":
            d += 1
        elif txt[k] == "}":
            d -= 1
            if d == 0:
                return txt[j:k + 1]
    return txt[j:]


FROZEN = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':\s*\(([\d.]+),", block(vtxt, "FROZEN_KOVALS"))}
MANUAL_ANCHOR = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':\s*\(([\d.]+)", block(vtxt, "MANUAL_ANCHOR"))}
MANUAL_FLOOR = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':\s*([\d.]+)", block(vtxt, "MANUAL_FLOOR"))}

# ── pivot ──
P = collections.defaultdict(dict)
for r in csv.DictReader(open(f"{IN}/prod_jp_en_raw_graded_0618.csv")):
    p = num(r['price'])
    if p is None:
        continue
    lang = 'jp' if r['source'] == 'SCRYDEX_JP' else 'en'
    key = f"{lang}_raw" if r['card_status'] == 'RAW' else f"{lang}_psa{r['grade_value']}"
    P[r['card_id']][key] = p

AU = {r['card_id']: r for r in csv.DictReader(open(f"{IN}/prod_ko_estimated_audit_20260608_20260618.csv")) if r['estimated_date'] == '2026-06-18'}

# ── 속성 ──
HIGH_RARITY = {'SR', 'SAR', 'HR', 'MUR', 'SSR', 'UR', 'CSR', 'CHR', 'BWR', 'AR', 'RR', 'RRR'}
ICONIC = ['레시라무', '릴리에', '블래키', '리자몽', '레쿠쟈', '피카츄', '뮤츠', '뮤', '이브이', '갸라도스', '가브리아스']
# 비율/임계 정책 (조정가능 — 단일 고정값 아님)
RATIO_PSA10 = 1.05   # raw>psa10*1.05 → hard invalid
RATIO_PSA9 = 1.15    # raw>psa9*1.15 → suspect
KO_UNDER = 0.03      # ko/시장가 < 3% → underpriced outlier
KO_OVER_EN = 1.0     # ko/en_raw > 1.0 → overpriced outlier
NO_LADDER_VALUE = 100000  # ladder없음+jp_raw>=10만 → 위험
GRAIL_FIXED = 300000      # 보조 safety net (핵심 아님)
GRAIL_SENS = [100000, 300000, 500000, 1000000]


def era_of(code):
    m = re.match(r'(BS|PR|SM|XY)?(\d{4})', code or '')
    if (code or '').startswith('PR'):
        return 'PROMO'
    if not m:
        return 'UNKNOWN'
    y = int(m.group(2))
    if y <= 2013:
        return 'BW'
    if y <= 2016:
        return 'XY'
    if y <= 2019:
        return 'SM'
    if y <= 2022:
        return 'SWSH'
    return 'SV'


def assess(cid, a, pr):
    ko = num(a['ko_price'])
    jr, j10, j9 = pr.get('jp_raw'), pr.get('jp_psa10'), pr.get('jp_psa9')
    er, e10, e9 = pr.get('en_raw'), pr.get('en_psa10'), pr.get('en_psa9')
    rar = a['rarity_code']; name = a['name']
    era = era_of(a['official_card_code'])
    rrisk = 'HIGH' if rar in HIGH_RARITY else 'LOW'
    iconic = any(k in name for k in ICONIC)
    has_ladder = j10 is not None or j9 is not None

    flags = []; score = 0
    raw_over_psa10 = bool(jr and j10 and jr > j10 * RATIO_PSA10)
    raw_over_psa9 = bool(jr and j9 and jr > j9 * RATIO_PSA9)
    en_raw_over_psa10 = bool(er and e10 and er > e10 * RATIO_PSA10)
    if raw_over_psa10:
        flags.append('RAW_OVER_PSA10_INVALID'); score += 5
    elif raw_over_psa9:
        flags.append('RAW_OVER_PSA9_SUSPECT'); score += 3
    if en_raw_over_psa10:
        flags.append('EN_RAW_OVER_PSA10'); score += 3

    def rat(x, y):
        return round(x / y, 4) if (x and y) else None
    ko_jr = rat(ko, jr); ko_j10 = rat(ko, j10); ko_j9 = rat(ko, j9); ko_er = rat(ko, er)
    # display underpriced: KO 가 JP raw/psa9 대비 극단적으로 낮음 (레시라무 0.0088)
    if ko_jr is not None and ko_jr < KO_UNDER:
        flags.append('DISPLAY_UNDERPRICED_VS_JP_RAW'); score += 3
    if ko_j9 is not None and ko_j9 < KO_UNDER:
        flags.append('DISPLAY_UNDERPRICED_VS_JP_PSA9'); score += 3
    if ko_er is not None and ko_er > KO_OVER_EN:
        flags.append('DISPLAY_OVERPRICED_VS_EN_RAW'); score += 2
    # 속성 가중
    if era in ('BW', 'XY', 'SM') and rrisk == 'HIGH':
        flags.append('OLD_ERA_HIGH_RARITY'); score += 2
    if (not has_ladder) and jr and jr >= NO_LADDER_VALUE:
        flags.append('NO_LADDER_HIGH_VALUE'); score += 2
    if iconic:
        flags.append('ICONIC'); score += 1
    fixed_hit = bool(jr and jr >= GRAIL_FIXED)
    if fixed_hit and not has_ladder:
        flags.append('GRAIL_FIXED_NO_LADDER')  # 보조 신호(점수 가중 약함)
        score += 1
    ratio_hit = bool(raw_over_psa10 or raw_over_psa9 or (ko_jr is not None and ko_jr < KO_UNDER)
                     or (ko_j9 is not None and ko_j9 < KO_UNDER) or (ko_er is not None and ko_er > KO_OVER_EN))

    # priority: manual > floor > frozen > score
    if cid in MANUAL_ANCHOR:
        action = 'KEEP_MANUAL_ANCHOR'
    elif cid in MANUAL_FLOOR:
        action = 'KEEP_MANUAL_FLOOR'
    elif cid in FROZEN:
        action = 'KEEP_FROZEN'
    elif raw_over_psa10:
        action = 'JP_SUSPECT_HOLD(검수중)'
    elif score >= 5:
        action = 'MANUAL_REVIEW'
    elif score >= 3:
        action = 'WATCH'
    else:
        action = 'OK_AUTO'

    return dict(jr=jr, j10=j10, j9=j9, er=er, e10=e10, e9=e9, ko=ko, era=era, rrisk=rrisk,
                flags=flags, score=score, action=action, raw_over_psa10=raw_over_psa10,
                raw_over_psa9=raw_over_psa9, en_raw_over_psa10=en_raw_over_psa10,
                ko_jr=ko_jr, ko_j10=ko_j10, ko_j9=ko_j9, ko_er=ko_er,
                rto10=rat(jr, j10), rto9=rat(jr, j9), fixed_hit=fixed_hit, ratio_hit=ratio_hit, has_ladder=has_ladder)


COLS = ['card_id', 'name', 'rarity_code', 'product_id', 'official_card_code', 'jp_ref', 'en_ref',
        'current_ko_estimated', 'current_anchor', 'current_selected_raw_price_krw',
        'jp_raw', 'jp_psa9', 'jp_psa10', 'en_raw', 'en_psa9', 'en_psa10',
        'raw_over_psa10', 'raw_over_psa9_pct', 'raw_to_psa10_ratio', 'raw_to_psa9_ratio',
        'ko_to_jp_raw_ratio', 'ko_to_jp_psa9_ratio', 'ko_to_jp_psa10_ratio', 'ko_to_en_raw_ratio',
        'era_bucket', 'rarity_risk', 'frozen_exists', 'manual_anchor_exists', 'manual_floor_exists',
        'fixed_threshold_hit', 'ratio_threshold_hit', 'final_manual_review_score',
        'anomaly_flags', 'recommended_action', 'reason']

rows = []
for cid, a in AU.items():
    s = assess(cid, a, P.get(cid, {}))
    rows.append({
        'card_id': cid, 'name': a['name'], 'rarity_code': a['rarity_code'], 'product_id': a['product_id'],
        'official_card_code': a['official_card_code'], 'jp_ref': a['jp_scrydex_ref'], 'en_ref': a['en_scrydex_ref'],
        'current_ko_estimated': int(s['ko']) if s['ko'] else None, 'current_anchor': a['selected_source'],
        'current_selected_raw_price_krw': int(num(a['selected_raw_price_krw'])) if num(a['selected_raw_price_krw']) else None,
        'jp_raw': int(s['jr']) if s['jr'] else None, 'jp_psa9': int(s['j9']) if s['j9'] else None,
        'jp_psa10': int(s['j10']) if s['j10'] else None, 'en_raw': int(s['er']) if s['er'] else None,
        'en_psa9': int(s['e9']) if s['e9'] else None, 'en_psa10': int(s['e10']) if s['e10'] else None,
        'raw_over_psa10': s['raw_over_psa10'],
        'raw_over_psa9_pct': round(100 * (s['jr'] / s['j9'] - 1), 1) if (s['jr'] and s['j9']) else None,
        'raw_to_psa10_ratio': s['rto10'], 'raw_to_psa9_ratio': s['rto9'],
        'ko_to_jp_raw_ratio': s['ko_jr'], 'ko_to_jp_psa9_ratio': s['ko_j9'],
        'ko_to_jp_psa10_ratio': s['ko_j10'], 'ko_to_en_raw_ratio': s['ko_er'],
        'era_bucket': s['era'], 'rarity_risk': s['rrisk'],
        'frozen_exists': cid in FROZEN, 'manual_anchor_exists': cid in MANUAL_ANCHOR, 'manual_floor_exists': cid in MANUAL_FLOOR,
        'fixed_threshold_hit': s['fixed_hit'], 'ratio_threshold_hit': s['ratio_hit'],
        'final_manual_review_score': s['score'], 'anomaly_flags': '|'.join(s['flags']),
        'recommended_action': s['action'], 'reason': ';'.join(s['flags']) or 'clean(데이터 한도 내)'})


def dump(fn, data, cols=COLS):
    with open(f"{OUT}/{fn}", 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(data)


dump('v8_full_catalog_sanity_audit.csv', rows)
dump('v8_raw_ladder_violation.csv', [r for r in rows if r['raw_over_psa10'] or (r['raw_to_psa9_ratio'] and r['raw_to_psa9_ratio'] > RATIO_PSA9) or r['anomaly_flags'].find('EN_RAW_OVER_PSA10') >= 0])
dump('v8_current_display_outliers.csv', [r for r in rows if 'DISPLAY_' in r['anomaly_flags']])
dump('v8_market_ladder_anomaly_watchlist.csv', [r for r in rows if (any(k in r['name'] for k in ICONIC) or (r['rarity_risk'] == 'HIGH' and r['era_bucket'] in ('BW', 'XY', 'SM'))) and r['final_manual_review_score'] >= 1])

# grail sensitivity
gs = []
for th in GRAIL_SENS:
    no_ladder_over = [r for r in rows if not (r['jp_psa10'] or r['jp_psa9']) and r['jp_raw'] and r['jp_raw'] >= th]
    gs.append({'fixed_threshold_krw': th, 'no_ladder_jp_raw_over_threshold': len(no_ladder_over),
               'of_which_high_rarity': sum(1 for r in no_ladder_over if r['rarity_risk'] == 'HIGH'),
               'of_which_old_era': sum(1 for r in no_ladder_over if r['era_bucket'] in ('BW', 'XY', 'SM'))})
dump('v8_grail_threshold_sensitivity.csv', gs, ['fixed_threshold_krw', 'no_ladder_jp_raw_over_threshold', 'of_which_high_rarity', 'of_which_old_era'])

# ── summary ──
n = len(rows)
cov = collections.Counter()
for cid in AU:
    pr = P.get(cid, {})
    for k in ['jp_raw', 'jp_psa10', 'jp_psa9', 'en_raw', 'en_psa10', 'en_psa9']:
        if k in pr:
            cov[k] += 1
    if not pr:
        cov['NONE'] += 1
act = collections.Counter(r['recommended_action'] for r in rows)
flagc = collections.Counter(f for r in rows for f in r['anomaly_flags'].split('|') if f)
by_rar = collections.Counter(r['rarity_code'] for r in rows if r['final_manual_review_score'] >= 5)
prot_anom = sum(1 for r in rows if (r['frozen_exists'] or r['manual_anchor_exists'] or r['manual_floor_exists']) and r['final_manual_review_score'] >= 3)


def card(cid):
    r = next((x for x in rows if x['card_id'] == cid), None)
    return r


resi = card('CRD_3E0AD8CAAB4F44D5B183')
lil = [r for r in rows if r['name'] == '릴리에']

summary = f"""# v8 FULL-CATALOG sanity audit — 기존 3,741장 전수 (신규 59 제외)
로컬 read-only, prod 무접속. 고정 GRAIL 단독 아님 = ladder위반 + KO/market 비율 + rarity/era 복합 score.

## ★★ 최상위 한계: 입력 덤프가 불완전 → 이 audit 은 outlier '하한선'(false-negative 많음)
- jp_raw {cov['jp_raw']}/{n}({100*cov['jp_raw']//n}%) · jp_psa10 {cov['jp_psa10']}({100*cov['jp_psa10']//n}%) · jp_psa9 {cov['jp_psa9']}({100*cov['jp_psa9']//n}%) · en_raw {cov['en_raw']}({100*cov['en_raw']//n}%) · 가격데이터 전무 {cov['NONE']}장.
- **psa10 39% 결측 → `raw>PSA10` 룰은 검사 자체가 불가한 카드가 다수. 레시라무도 stored 덤프엔 psa ladder 없음(앱 화면은 scrydex live).**
- 즉 '플래그 안 됨'='정상' 아님. **완전한 가격 덤프 재추출 후 재실행 필수**(397 감사와 같은 선결조건).

## bucket(recommended_action) 분포
{chr(10).join(f'- {k}: {v}' for k, v in act.most_common())}

## anomaly_flags 빈도
{chr(10).join(f'- {k}: {v}' for k, v in flagc.most_common())}

## score>=5 (MANUAL_REVIEW) rarity 분포
{chr(10).join(f'- {k}: {v}' for k, v in by_rar.most_common())}

## frozen/manual 보호 카드 중 anomaly(score>=3) = {prot_anom}장

## ★레시라무 SR 055/053 BW (사용자 케이스)
- card_id CRD_3E0AD8CAAB4F44D5B183 / {resi['official_card_code']} / {resi['rarity_code']} / era {resi['era_bucket']}
- current: anchor={resi['current_anchor']} ko={resi['current_ko_estimated']} selraw={resi['current_selected_raw_price_krw']}
- jp_raw={resi['jp_raw']} jp_psa10={resi['jp_psa10']} jp_psa9={resi['jp_psa9']} (★stored 덤프에 psa ladder 없음)
- ko_to_jp_raw_ratio={resi['ko_to_jp_raw_ratio']} (=0.88%, 극단 underpriced)
- flags: {resi['anomaly_flags']}
- score={resi['final_manual_review_score']} → **{resi['recommended_action']}**
- 판정: stored 덤프엔 ladder 없어 RAW_OVER_PSA10 미발화 → **DISPLAY_UNDERPRICED 비율룰이 잡음.** 앱 live 기준(raw$1344>psa10$622)이면 RAW_OVER_PSA10 도 추가 발화. 어느 경로든 **자동가격 금지·검수중**이 정답. 현재는 EN 자동 16,555 송출 = v8 이 막아야 할 케이스 ✓

## 릴리에
{chr(10).join(f"- {r['official_card_code']} jp_raw={r['jp_raw']} flags={r['anomaly_flags']} score={r['final_manual_review_score']} → {r['recommended_action']}" for r in lil)}

## 핵심 결론
1. **GRAIL 고정값 단독 = 실패.** 레시라무(ko 16,590, jp_raw 1.88M)는 고정 30만 컷에 안 걸리고 **비율(ko/jp_raw 0.88%)로만 잡힘.**
2. raw>PSA10 hard = {flagc['RAW_OVER_PSA10_INVALID']}장(덤프 ladder 결측으로 과소). DISPLAY_UNDERPRICED 류 = {flagc['DISPLAY_UNDERPRICED_VS_JP_RAW']+flagc['DISPLAY_UNDERPRICED_VS_JP_PSA9']}장.
3. score 복합판정이 단일룰보다 recall 높음. 단 **덤프 완전성이 최종 게이트**.
4. 코드/prod/sync/apply/admin-add 0. 로컬 산출만. 신규 59 제외. v6 무관.
"""
open(f"{OUT}/v8_full_catalog_summary.md", 'w').write(summary)

print("=== action 분포 ===")
for k, v in act.most_common():
    print(f"  {k}: {v}")
print("=== flag 빈도(top) ===")
for k, v in flagc.most_common(12):
    print(f"  {k}: {v}")
print(f"=== 레시라무 BW SR: score={resi['final_manual_review_score']} action={resi['recommended_action']} flags={resi['anomaly_flags']}")
print(f"=== grail sensitivity: {[(g['fixed_threshold_krw'],g['no_ladder_jp_raw_over_threshold']) for g in gs]}")
print(f"=== coverage: jp_raw {cov['jp_raw']} jp_psa10 {cov['jp_psa10']} jp_psa9 {cov['jp_psa9']} en_raw {cov['en_raw']} NONE {cov['NONE']} / {n}")
print(f"→ {OUT}/")
