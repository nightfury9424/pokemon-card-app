#!/usr/bin/env python3
"""거절(REJECTED/NO_VALID) 카드 재매칭 = 이미지 아닌 [세트+번호 + 이름 + 레어도] 기반.
- jp_ref(set+number)로 SNK 직접 조회 (이미지 스캐너가 놓친 정답 회수)
- 이름 검증: 승인된 카드들에서 KO→JP 이름맵 구축 → 오매칭(쥬피썬더→Focus Sash) 걸러냄
- 레어도: SNK rarity 컬럼 비면 jp_title에서 파싱
출력: snkrdunk_rematch_candidates.csv (재검색 라운드용)
"""
import os, csv, re, sqlite3, json
from collections import defaultdict, Counter

SNK = os.path.expanduser("~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv")
CATALOG = "python/catalog_gapfill/prod_cards_full_20260620.csv"
DB = "python/price_v8/snkrdunk_review.sqlite"
OUT = "python/price_v8/snkrdunk_rematch_candidates.csv"
SKIP_RARITY = {"S", "A", "K"}

def numint(s):
    m = re.search(r"(\d+)", s or ""); return int(m.group(1)) if m else None

# jp_title: "メガヤンマex RR [M2a 003/193](...)" → name=메가야끼ex, rarity=RR
RAR_TOKENS = {"SR","SAR","AR","HR","UR","RR","RRR","SSR","CHR","CSR","PR","MA","MUR","BWR","S","A","K"}
def parse_title(t):
    t = t or ""
    base = t.split("[")[0].strip()           # "メガヤンマex RR "
    toks = base.split()
    rar = ""
    if toks and toks[-1] in RAR_TOKENS:
        rar = toks[-1]; toks = toks[:-1]
    name = "".join(toks) if not " " in base else " ".join(toks)
    return name.strip(), rar

# ---- SNK 로드 + 인덱스 ----
snk = list(csv.DictReader(open(SNK, encoding="utf-8")))
for r in snk:
    nm, rar = parse_title(r["jp_title"])
    r["_name"] = nm
    r["_rar"] = (r.get("rarity") or rar or "").upper()
    r["_num"] = numint(r["number"])
    r["_set"] = (r["set"] or "").lower()
by_setnum = defaultdict(list)
by_name = defaultdict(list)
for r in snk:
    by_setnum[(r["_set"], r["_num"])].append(r)
    if r["_name"]: by_name[r["_name"]].append(r)

# ---- 우리 카탈로그 ----
meta = {r["card_id"]: r for r in csv.DictReader(open(CATALOG, encoding="utf-8"))}
def jpsetnum(ref):
    m = re.match(r"^([a-z0-9]+)_ja-(\d+)", (ref or "").lower())
    return (m.group(1), int(m.group(2))) if m else (None, None)

# ---- 승인 카드에서 KO→JP 이름맵 ----
con = sqlite3.connect(DB); con.row_factory = sqlite3.Row
appr = {r["our_card_id"]: r["snkrdunk_apparel_id"] for r in
        con.execute("SELECT our_card_id,snkrdunk_apparel_id FROM review_decisions WHERE decision='APPROVED' AND snkrdunk_apparel_id!=''")}
snk_by_aid = {str(r["apparel_id"]): r for r in snk}
ko2jp = defaultdict(Counter)
for cid, aid in appr.items():
    m = meta.get(cid); s = snk_by_aid.get(str(aid))
    if m and s and s["_name"]:
        ko2jp[m["name"]][s["_name"]] += 1
ko2jp_best = {k: c.most_common(1)[0][0] for k, c in ko2jp.items()}
print(f"[이름맵] 승인 {len(appr)}장에서 KO→JP 이름 {len(ko2jp_best)}종 학습")

# 종족(suffix 제거) 레벨 맵 + SNK 종족 인덱스 — NO_JP/jp_ref 어긋난 카드 구제용
SUF = ["VMAX","VSTAR","VUNION","V-UNION","ex","EX","GX","BREAK","LEGEND","V","δ","◇","☆","&"]
def species(n):
    n = (n or "").strip()
    changed = True
    while changed:
        changed = False
        for s in sorted(SUF, key=len, reverse=True):
            if n.endswith(s) and len(n) > len(s):
                n = n[:-len(s)].strip(); changed = True
    return n
ko2jpsp = defaultdict(Counter)
for cid, aid in appr.items():
    m = meta.get(cid); s = snk_by_aid.get(str(aid))
    if m and s and s["_name"]:
        ko2jpsp[species(m["name"])][species(s["_name"])] += 1
ko2jpsp_best = {k: c.most_common(1)[0][0] for k, c in ko2jpsp.items() if k}
by_sp = defaultdict(list)
for r in snk:
    if r["_name"]: by_sp[species(r["_name"])].append(r)
print(f"[종족맵] KO→JP 종족 {len(ko2jpsp_best)}종")

# ---- 거절 카드 재매칭 ----
rej = [r["our_card_id"] for r in con.execute(
    "SELECT our_card_id FROM review_decisions WHERE decision IN ('REJECTED','NO_VALID_CANDIDATE')")]
rows_out = []
stat = Counter()
for cid in rej:
    m = meta.get(cid)
    if not m: continue
    if (m.get("rarity_code") or "").upper() in SKIP_RARITY:  # S/A/K 제외(이미 빠진 카드)
        stat["skip_ska"] += 1; continue
    our_rar = (m.get("rarity_code") or "").upper()
    s, n = jpsetnum(m.get("jp_scrydex_ref"))
    exp_jp = ko2jp_best.get(m["name"])   # 이름맵으로 기대 JP명(있으면)
    cands = {}
    # 1) 세트+번호
    for r in by_setnum.get((s, n), []):
        cands[str(r["apparel_id"])] = (r, 3)
    # 2) 이름(+레어도) — 기대 JP명이 있으면 그걸로, 전 세트 검색
    if exp_jp:
        for r in by_name.get(exp_jp, []):
            aid = str(r["apparel_id"])
            base = cands[aid][1] if aid in cands else 0
            cands[aid] = (r, base + 2)
    # 3) 종족 fuzzy(+레어도) — NO_JP/jp_ref 어긋난 카드 구제. 같은 종족+같은 레어도만.
    exp_sp = ko2jpsp_best.get(species(m["name"]))
    if exp_sp:
        for r in by_sp.get(exp_sp, []):
            if our_rar and r["_rar"] and r["_rar"] != our_rar: continue   # 레어도 다르면 스킵
            aid = str(r["apparel_id"])
            if aid not in cands: cands[aid] = (r, 1)
    # 점수 = 세트번호(3) + 이름(2) + 레어도일치(1) + 이름맵확증(1)
    scored = []
    for aid, (r, base) in cands.items():
        sc = base
        if our_rar and r["_rar"] == our_rar: sc += 1
        if exp_jp and r["_name"] == exp_jp: sc += 1
        scored.append((sc, r))
    scored.sort(key=lambda x: -x[0])
    if not scored:
        stat["no_match"] += 1; continue
    stat["matched"] += 1
    if scored[0][0] >= 5: stat["strong"] += 1   # 세트번호+레어도 또는 +이름
    top5 = [str(r["apparel_id"]) for _, r in scored[:8]]
    for rank, (sc, r) in enumerate(scored[:8], 1):
        rows_out.append({
            "our_card_id": cid, "our_name": m["name"], "our_jp_ref": m.get("jp_scrydex_ref",""),
            "our_rarity": our_rar,
            "snkrdunk_apparel_id": r["apparel_id"], "snkrdunk_product_number": r["product_number"],
            "snkrdunk_title": r["jp_title"], "snkrdunk_image_url": r["image_url"],
            "rematch_rank": rank, "rematch_score": sc,
            "snk_set": r["set"], "snk_number": r["number"], "snk_rarity": r["_rar"],
            "set_number_check": "OK" if (r["_set"], r["_num"]) == (s, n) else "DIFF",
            "rarity_check": "OK" if (our_rar and r["_rar"] == our_rar) else "DIFF",
            "name_check": "OK" if (exp_jp and r["_name"] == exp_jp) else ("NO_MAP" if not exp_jp else "DIFF"),
        })

with open(OUT, "w", encoding="utf-8", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows_out[0].keys()))
    w.writeheader(); w.writerows(rows_out)

print(f"\n=== 거절 {len(rej)}장 재매칭 결과 ===")
print(f"  매칭됨: {stat['matched']} (그중 강한확신 세트번호+레어도/이름 {stat['strong']})")
print(f"  매칭실패: {stat['no_match']} · S/A/K스킵: {stat['skip_ska']}")
print(f"  출력: {OUT} ({len(rows_out)}행, 카드당 최대5후보)")
