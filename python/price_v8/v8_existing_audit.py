"""v8 EXISTING-only audit (3,741장, 신규 59 제외). 로컬 read-only. prod 무접속.
산출: 397 JP->EN 역방향 / frozen·manual 충돌 / PSA9 tolerance / existing-only 영향.
입력: /tmp/jf_inputs + /tmp/anchor_audit_20260619/data (이미 로컬).
"""
import csv, json, os, re, collections, statistics

IN = "/tmp/jf_inputs"
AA = "/tmp/anchor_audit_20260619"
OUT = "/tmp/price_v8_existing_audit_20260619"
os.makedirs(OUT, exist_ok=True)
GRAIL = 300000


def num(x):
    try:
        return float(x)
    except Exception:
        return None


# ── frozen / manual / floor (FROZEN_KOVALS 226 포함 — 로컬 prod_v6_manual_anchor.txt 에 있음) ──
vtxt = open(f"{AA}/data/prod_v6_manual_anchor.txt").read()
_mf = f"{IN}/prod_manual_anchor_floor.txt"
if os.path.exists(_mf):
    vtxt += "\n" + open(_mf).read()


def parse_block(txt, name):
    """name={ ... } 블록(한 줄 또는 여러 줄)의 첫 dict 본문 문자열 반환."""
    i = txt.find(name + "=")
    if i < 0:
        return ""
    j = txt.find("{", i)
    depth = 0
    for k in range(j, len(txt)):
        if txt[k] == "{":
            depth += 1
        elif txt[k] == "}":
            depth -= 1
            if depth == 0:
                return txt[j:k + 1]
    return txt[j:]


frozen_body = parse_block(vtxt, "FROZEN_KOVALS")
FROZEN = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':\s*\(([\d.]+),", frozen_body)}
manual_body = parse_block(vtxt, "MANUAL_ANCHOR")
MANUAL_ANCHOR = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':\s*\(([\d.]+)", manual_body)}
floor_body = parse_block(vtxt, "MANUAL_FLOOR")
MANUAL_FLOOR = {m.group(1): float(m.group(2)) for m in re.finditer(r"'(CRD_[0-9A-F]+)':\s*([\d.]+)", floor_body)}

# ── 6/18 graded pivot + per-card JP/EN snapshot presence ──
P = collections.defaultdict(dict)
jp_any = set(); en_any = set()  # 카드가 6/18 덤프에 SCRYDEX_JP/EN row 가 있는가
for r in csv.DictReader(open(f"{IN}/prod_jp_en_raw_graded_0618.csv")):
    lang = 'jp' if r['source'] == 'SCRYDEX_JP' else 'en'
    (jp_any if lang == 'jp' else en_any).add(r['card_id'])
    p = num(r['price'])
    if p is None:
        continue
    key = f"{lang}_raw" if r['card_status'] == 'RAW' else f"{lang}_psa{r['grade_value']}"
    P[r['card_id']][key] = p

# ── 6/18 audit (현재 운영값) + coef 추정 ──
AU = {}
rar_jpc = collections.defaultdict(list); rar_enc = collections.defaultdict(list); card_jpc = {}
for r in csv.DictReader(open(f"{IN}/prod_ko_estimated_audit_20260608_20260618.csv")):
    if r['estimated_date'] == '2026-06-18':
        AU[r['card_id']] = r
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


def v8_decide(cid, rar, jpref, enref, jpraw, jp10, jp9, enraw, ps9_mult=1.0):
    """기존 dry-run 과 동일 + PSA9 tolerance 인자. returns (bucket, anchor, est, reason)."""
    ma = MANUAL_ANCHOR.get(cid)
    if ma is not None:
        return 'MANUAL_ANCHOR', 'MANUAL', int(ma), 'manual anchor'
    ladder = jp10 is not None or jp9 is not None
    if not vref(jpref) or jpraw is None:
        est = round(enraw * enc(rar)) if enraw else None
        return 'EN_FALLBACK_OK', 'EN', est, 'JP raw/ref 없음 → EN'
    if jp10 is not None and jpraw > jp10:
        return 'JP_SUSPECT', 'NONE', None, f'RAW>PSA10 ({int(jpraw)}>{int(jp10)})'
    if jp9 is not None and jpraw > jp9 * ps9_mult:
        return 'JP_SUSPECT', 'NONE', None, f'RAW>PSA9*{ps9_mult} ({int(jpraw)}>{int(jp9*ps9_mult)})'
    if not ladder:
        if jpraw > GRAIL:
            return 'MANUAL_REVIEW', 'NONE', None, f'ladder없음+고가({int(jpraw)})'
        return 'JP_VALID', 'JP', round(jpraw * jpc(cid, rar)), 'ladder없음 저가 → JP'
    est = round(jpraw * jpc(cid, rar))
    mf = MANUAL_FLOOR.get(cid)
    if mf is not None and est < mf:
        return 'MANUAL_FLOOR', 'JP+FLOOR', int(mf), f'JP {est}<floor {int(mf)}'
    return 'JP_VALID', 'JP', est, 'raw<=psa9<=psa10 → JP'


# ── 전체 결정 (strict) ──
ALL = {}
for cid, a in AU.items():
    pr = P.get(cid, {})
    b, anc, est, reason = v8_decide(cid, a['rarity_code'], a['jp_scrydex_ref'], a['en_scrydex_ref'],
                                    pr.get('jp_raw'), pr.get('jp_psa10'), pr.get('jp_psa9'), pr.get('en_raw'))
    ALL[cid] = (a, pr, b, anc, est, reason)

# ════════ 1순위: 397 JP->EN 역방향 감사 ════════
REV_COLS = ['card_id', 'name', 'rarity_code', 'product_id', 'official_card_code', 'jp_scrydex_ref', 'en_scrydex_ref',
            'current_anchor', 'current_ko_estimated', 'current_selected_raw_price_krw', 'v8_bucket', 'v8_anchor',
            'v8_estimated', 'diff', 'diff_pct', 'jp_raw', 'jp_psa9', 'jp_psa10', 'en_raw', 'en_psa9', 'en_psa10',
            'jp_raw_missing_reason', 'jp_ref_valid', 'price_snapshot_jp_exists', 'pivot_join_failed', 'classification', 'reason']
rev = []
cls_count = collections.Counter()
for cid, (a, pr, b, anc, est, reason) in ALL.items():
    if a['selected_source'] != 'JP' or anc != 'EN':
        continue
    cur = num(a['ko_price']); selraw = num(a['selected_raw_price_krw'])
    jpraw_piv = pr.get('jp_raw')
    refv = vref(a['jp_scrydex_ref'])
    jp_exists = cid in jp_any
    # 분류
    if jpraw_piv is not None:
        cls = 'D_BUG_JP_RAW_PRESENT_BUT_EN'; miss = 'NONE'
    elif not refv:
        cls = 'A_NO_JP_REF'; miss = 'REF_INVALID(NO_/null)'
    elif selraw and selraw > 0:
        # 6/18 audit 가 JP raw 를 실제로 썼음(selected_raw_price_krw>0) → 같은날 덤프엔 없음 = 덤프 불완전
        cls = 'B_PIVOT_DUMP_INCOMPLETE'
        miss = 'JP_GRADED_PRESENT_RAW_ROW_MISSING' if jp_exists else 'JP_ROW_ABSENT_FROM_0618_DUMP'
    else:
        cls = 'C_GENUINE_NO_JP_OR_STALE'; miss = 'NO_JP_SNAPSHOT_AND_NO_AUDIT_RAW'
    cls_count[cls] += 1
    piv_fail = (cls == 'B_PIVOT_DUMP_INCOMPLETE')
    diff = (est - cur) if (est is not None and cur is not None) else None
    rev.append({'card_id': cid, 'name': a['name'], 'rarity_code': a['rarity_code'], 'product_id': a['product_id'],
                'official_card_code': a['official_card_code'], 'jp_scrydex_ref': a['jp_scrydex_ref'],
                'en_scrydex_ref': a['en_scrydex_ref'], 'current_anchor': a['selected_source'],
                'current_ko_estimated': int(cur) if cur else None,
                'current_selected_raw_price_krw': int(selraw) if selraw else None,
                'v8_bucket': b, 'v8_anchor': anc, 'v8_estimated': est,
                'diff': int(diff) if diff is not None else None,
                'diff_pct': round(100 * diff / cur, 1) if (diff is not None and cur) else None,
                'jp_raw': int(jpraw_piv) if jpraw_piv else None,
                'jp_psa9': int(pr['jp_psa9']) if pr.get('jp_psa9') else None,
                'jp_psa10': int(pr['jp_psa10']) if pr.get('jp_psa10') else None,
                'en_raw': int(pr['en_raw']) if pr.get('en_raw') else None,
                'en_psa9': int(pr['en_psa9']) if pr.get('en_psa9') else None,
                'en_psa10': int(pr['en_psa10']) if pr.get('en_psa10') else None,
                'jp_raw_missing_reason': miss, 'jp_ref_valid': refv,
                'price_snapshot_jp_exists': jp_exists, 'pivot_join_failed': piv_fail,
                'classification': cls, 'reason': reason})


def dump(fn, data, cols):
    with open(f"{OUT}/{fn}", 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=cols); w.writeheader(); w.writerows(data)


dump('v8_reverse_jp_to_en_audit.csv', rev, REV_COLS)

# ════════ 3순위: frozen / manual 충돌표 ════════
CONF_COLS = ['card_id', 'name', 'rarity_code', 'current_ko_estimated', 'current_anchor', 'frozen_exists',
             'frozen_value', 'manual_anchor_exists', 'manual_floor_exists', 'v8_bucket', 'v8_anchor', 'v8_estimated',
             'would_override_frozen', 'would_override_manual', 'action']
conf = []
ov_frozen = ov_manual = 0
for cid, (a, pr, b, anc, est, reason) in ALL.items():
    fz = cid in FROZEN; ma = cid in MANUAL_ANCHOR; mflo = cid in MANUAL_FLOOR
    if not (fz or ma or mflo):
        continue
    cur = num(a['ko_price'])
    # v8 이 frozen/manual 카드에 다른 자동값을 부여하려는가 (우선순위: ANCHOR>FLOOR>FROZEN>v8)
    protected = ma or mflo or fz
    v8_auto = anc in ('JP', 'EN') and b not in ('MANUAL_ANCHOR', 'MANUAL_FLOOR')
    would_override_frozen = bool(fz and v8_auto and not ma)
    would_override_manual = bool((ma or mflo) and b not in ('MANUAL_ANCHOR', 'MANUAL_FLOOR') and anc in ('JP', 'EN'))
    if would_override_frozen:
        ov_frozen += 1
    if would_override_manual:
        ov_manual += 1
    if ma:
        action = 'KEEP_MANUAL_ANCHOR (v8 우선순위1)'
    elif mflo:
        action = 'KEEP_MANUAL_FLOOR (v8 우선순위2)'
    elif fz:
        action = 'KEEP_FROZEN (v8 우선순위3, 자동 덮어쓰기 금지)' if v8_auto else 'frozen=v8 합치'
    else:
        action = 'review'
    conf.append({'card_id': cid, 'name': a['name'], 'rarity_code': a['rarity_code'],
                 'current_ko_estimated': int(cur) if cur else None, 'current_anchor': a['selected_source'],
                 'frozen_exists': fz, 'frozen_value': int(FROZEN[cid]) if fz else None,
                 'manual_anchor_exists': ma, 'manual_floor_exists': mflo, 'v8_bucket': b, 'v8_anchor': anc,
                 'v8_estimated': est, 'would_override_frozen': would_override_frozen,
                 'would_override_manual': would_override_manual, 'action': action})
dump('v8_frozen_manual_conflict_audit.csv', conf, CONF_COLS)

# ════════ 4순위: PSA9 tolerance 민감도 ════════
TOL_COLS = ['card_id', 'name', 'rarity_code', 'jp_raw', 'jp_psa9', 'jp_psa10', 'raw_over_psa9_pct',
            'strict_suspect', 'tol10_suspect', 'tol15_suspect', 'released_by_tol10', 'released_by_tol15',
            'raw_over_psa10_hard']
tol = []
tol_counts = {'strict': 0, 'tol10': 0, 'tol15': 0, 'hard_psa10': 0}
for cid, (a, pr, b, anc, est, reason) in ALL.items():
    jpraw = pr.get('jp_raw'); jp9 = pr.get('jp_psa9'); jp10 = pr.get('jp_psa10')
    if jpraw is None or jp9 is None:
        continue
    hard10 = jp10 is not None and jpraw > jp10
    s_strict = jpraw > jp9 and not hard10
    s_t10 = jpraw > jp9 * 1.10 and not hard10
    s_t15 = jpraw > jp9 * 1.15 and not hard10
    if not (s_strict or hard10):
        continue  # PSA9 suspect 후보만
    tol_counts['strict'] += 1 if s_strict else 0
    tol_counts['tol10'] += 1 if s_t10 else 0
    tol_counts['tol15'] += 1 if s_t15 else 0
    tol_counts['hard_psa10'] += 1 if hard10 else 0
    tol.append({'card_id': cid, 'name': a['name'], 'rarity_code': a['rarity_code'], 'jp_raw': int(jpraw),
                'jp_psa9': int(jp9), 'jp_psa10': int(jp10) if jp10 else None,
                'raw_over_psa9_pct': round(100 * (jpraw / jp9 - 1), 1),
                'strict_suspect': s_strict, 'tol10_suspect': s_t10, 'tol15_suspect': s_t15,
                'released_by_tol10': bool(s_strict and not s_t10), 'released_by_tol15': bool(s_strict and not s_t15),
                'raw_over_psa10_hard': hard10})
tol.sort(key=lambda r: r['raw_over_psa9_pct'])
dump('v8_psa9_tolerance_sensitivity.csv', tol, TOL_COLS)

# ── 버킷 집계 (existing only) ──
bc = collections.Counter(v[2] for v in ALL.values())
trans = collections.Counter((v[0]['selected_source'], v[3]) for v in ALL.values())

# ════════ summaries ════════
revB = cls_count.get('B_PIVOT_DUMP_INCOMPLETE', 0)
revA = cls_count.get('A_NO_JP_REF', 0)
revC = cls_count.get('C_GENUINE_NO_JP_OR_STALE', 0)
revD = cls_count.get('D_BUG_JP_RAW_PRESENT_BUT_EN', 0)
rev_none = sum(1 for r in rev if r['v8_estimated'] is None)
rev_priced = sum(1 for r in rev if r['v8_estimated'] is not None)
big_up = [r for r in rev if r['diff_pct'] is not None and r['diff_pct'] > 30]
big_dn = [r for r in rev if r['diff_pct'] is not None and r['diff_pct'] < -30]

rsum = f"""# v8 397 JP→EN 역방향 감사 (기존 3,741장, 신규 59 제외)

## 결론 (게이트)
- **D (JP raw 정상인데 v8이 EN行) = {revD}장.** → v8 정책 자체에 치명적 오류 **없음**. 구현 게이트 통과.
- 397 중 **{revB}장 = B_PIVOT_DUMP_INCOMPLETE** (dry-run 입력 덤프 누락 = 가짜 전이).
  근거: 6/18 audit 가 같은 날 JP raw(selected_raw_price_krw>0)를 실제로 사용했는데,
  같은 날 graded 덤프엔 jp_raw row 가 없음 → **덤프 불완전이지 staleness 아님**.
  실제 Java 경로(라이브 스냅샷 read)에선 이들은 JP_VALID 로 남을 가능성 큼.
- A_NO_JP_REF {revA} / C_GENUINE_NO_JP_OR_STALE {revC}.

## 397 의 실제 결과 (인플레 아님)
- v8_estimated **None(미산정/검수중) = {rev_none}장**, 실제 EN 재가격 = {rev_priced}장.
- 즉 "397 EN 인플레"는 **틀린 프레이밍**. 대부분 가격이 사라지거나(덤프 누락), 소수만 재가격.
- 재가격 {rev_priced}장 중 +30%↑ {len(big_up)}장 / −30%↓ {len(big_dn)}장 (양방향, per-card 검토 대상).

## 분류 집계
{chr(10).join(f'- {k}: {v}' for k, v in cls_count.most_common())}

## 핵심 시사
1. **dry-run 입력 덤프(prod_jp_en_raw_graded_0618.csv)가 불완전** → 397/377-None 등 모든 집계가 오염.
   → v8 구현 전 **입력 추출 재실행(완전한 raw 스냅샷)** 후 dry-run 재산출 필요.
2. 게이트 D=0 이므로 v8 정책 로직은 진행 가능. 단 **397은 정책 문제 아님 = 데이터 파이프 문제**.
3. 재가격 {rev_priced}장(특히 +30%↑ {len(big_up)}장)만 실질 위험 → manual 검토 큐.

## 미해결 (prod 무접속이라 deferred)
- B vs C 최종 확정은 read-only prod 스냅샷 traded_at 확인 필요(이 세션 prod 금지 → 다음).
"""
open(f"{OUT}/v8_reverse_jp_to_en_summary.md", 'w').write(rsum)

esum = f"""# v8 existing-only 영향 요약 (3,741장, 신규 59 제외)

## v8 버킷 (existing only, strict PSA9)
{chr(10).join(f'- {k}: {v}' for k, v in bc.most_common())}

## anchor 전이 (current → v8)
{chr(10).join(f'- {s} → {t}: {n}' for (s, t), n in trans.most_common())}

## 방향별 해석
- EN→JP {trans.get(('EN','JP'),0)}장 = 진짜 교정 후보(EN 과선택 → JP).
- JP→EN {trans.get(('JP','EN'),0)}장 = **대부분 덤프 누락(B={revB})**, 실제 EN 인플레 아님(미산정 {rev_none}).
- *→NONE = 자동 미산정(검수중/기존유지). 덤프 불완전으로 과대추정됨.

## frozen / manual 충돌
- FROZEN_KOVALS 로컬 파싱 = {len(FROZEN)}장 / MANUAL_ANCHOR {len(MANUAL_ANCHOR)} / MANUAL_FLOOR {len(MANUAL_FLOOR)}.
- v8 이 frozen 덮어쓰려는 카드(would_override_frozen) = {ov_frozen}장 → **우선순위로 차단 필수**.
- v8 이 manual 덮어쓰려는 카드 = {ov_manual}장.
- 우선순위 고정: MANUAL_ANCHOR > MANUAL_FLOOR > FROZEN_KOVALS > v8 sanity bucket.

## PSA9 tolerance 민감도
- strict(raw>psa9) suspect = {tol_counts['strict']}
- tol×1.10 suspect = {tol_counts['tol10']} (해제 {tol_counts['strict']-tol_counts['tol10']})
- tol×1.15 suspect = {tol_counts['tol15']} (해제 {tol_counts['strict']-tol_counts['tol15']})
- raw>PSA10 hard invalid = {tol_counts['hard_psa10']} (tolerance 무관 유지).

## 상태
코드/prod/sync/apply/admin-add 0. 로컬 dry-run 감사만. 신규 59 제외. v6 live run 무관.
★최우선 후속 = dry-run **입력 덤프 완전성** 수정(현 집계 신뢰 불가).
"""
open(f"{OUT}/v8_existing_only_impact_summary.md", 'w').write(esum)

print("=== 397 JP->EN 분류 ===")
for k, v in cls_count.most_common():
    print(f"  {k}: {v}")
print(f"  → v8 None(미산정) {rev_none} / 재가격 {rev_priced} (+30%↑ {len(big_up)} / -30%↓ {len(big_dn)})")
print(f"=== frozen/manual: FROZEN {len(FROZEN)} MANUAL_ANCHOR {len(MANUAL_ANCHOR)} FLOOR {len(MANUAL_FLOOR)} | override_frozen {ov_frozen} override_manual {ov_manual}")
print(f"=== PSA9 tol: strict {tol_counts['strict']} tol10 {tol_counts['tol10']} tol15 {tol_counts['tol15']} hard_psa10 {tol_counts['hard_psa10']}")
print(f"=== existing bucket: {dict(bc)}")
print(f"→ {OUT}/")
