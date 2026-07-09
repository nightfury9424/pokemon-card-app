#!/usr/bin/env python3
"""프로모/잔여 갭 스코프 — 최종 매핑 전에 우리 카탈로그 프로모 갭을 정리하기 위한 리포트.

문제: 우리 DB에 없는 프로모는 스캐너 인덱스에도 없어서, SNK 프로모 이미지가 들어오면
      가장 비슷한 기존 카드로 오매칭될 수 있음. → 프로모 채운 뒤 재인덱싱/재스캔해야 안전.

산출: snkrdunk_promo_gap_scope.csv (우리쪽 프로모/NO_JP/PR + SNK 미매핑 프로모)
read-only: DB write 0.
"""
import csv, json, os, re
from collections import defaultdict, Counter

ROOT = "/Users/fury/pokemon-card-app"
CATALOG = f"{ROOT}/python/catalog_gapfill/prod_cards_full_20260620.csv"
SNK = os.path.expanduser("~/pokefolio_backups/snkrdunk_catalog_20260620/snkrdunk_apparel_catalog_scanned.csv")
CAND = f"{ROOT}/python/price_v8/snkrdunk_registered_image_candidates.csv"
JSONL = f"{ROOT}/python/price_v8/snk_scan_results.jsonl"
OUT = f"{ROOT}/python/price_v8/snkrdunk_promo_gap_scope.csv"
HI = 0.75

def is_en(jp_title, en_name): return ("英語版" in (jp_title or "")) or ("[EN]" in (en_name or ""))
def num_int(s):
    m = re.search(r"(\d+)", str(s or "").split("/")[0].split("-")[-1]); return int(m.group(1)) if m else None
PROMO_PAT = re.compile(r"-P-|-P\]|-P$|プロモ|PROMO", re.I)
def snk_is_promo(pn, title):
    return bool(PROMO_PAT.search((pn or "") + " " + (title or "")) or " P [" in (title or ""))
def our_is_promo(ref):
    return bool(re.search(r"-?p_ja-|^[a-z]+p_ja-", (ref or "").lower())) or "-p_ja" in (ref or "").lower()

# 우리 카탈로그
reg = {}
for r in csv.DictReader(open(CATALOG, encoding="utf-8")):
    m = re.match(r"^([a-z0-9]+)_ja-(\d+)", (r.get("jp_scrydex_ref") or ""))
    reg[r["card_id"]] = {"name": r["name"], "ref": (r.get("jp_scrydex_ref") or ""), "rarity": r["rarity_code"],
                         "set": (m.group(1).upper() if m else ""), "num": (int(m.group(2)) if m else None),
                         "coll": r["collection_number"]}

# SNK 메타
snk = {}
for r in csv.DictReader(open(SNK, encoding="utf-8")):
    aid = str(r["apparel_id"])
    snk[aid] = {"pn": r.get("product_number",""), "title": r.get("jp_title",""),
                "img": r.get("image_url",""), "set": (r.get("set") or "").upper(),
                "num": num_int(r.get("number")), "rarity": r.get("rarity",""),
                "en": is_en(r.get("jp_title"), r.get("en_name")),
                "promo": snk_is_promo(r.get("product_number"), r.get("jp_title"))}

# 스캔결과 top1/top5
top = {}
for line in open(JSONL, encoding="utf-8"):
    try: d = json.loads(line)
    except: continue
    top[d["aid"]] = {"t1": d.get("top1") or {}, "t5": d.get("top5") or []}

# 우리카드 -> best 후보(JP만)
cand_by_card = defaultdict(list)
for r in csv.DictReader(open(CAND, encoding="utf-8")):
    s = snk.get(r["snkrdunk_apparel_id"], {})
    if s.get("en"): continue
    cand_by_card[r["our_card_id"]].append(r)
for cid in cand_by_card:
    cand_by_card[cid].sort(key=lambda x:(int(x["scanner_rank"] or 9), -(float(x["scanner_score"]) if x["scanner_score"] else 0)))

rows = []
def best_cand(cid):
    cs = cand_by_card.get(cid)
    return cs[0] if cs else None

# ── 1) 우리쪽 갭 (NO_JP / PR / promo-pattern) ──
seen_our = set()
for cid, o in reg.items():
    gtypes = []
    if not o["set"]: gtypes.append("OUR_NO_JP")
    if o["rarity"] == "PR": gtypes.append("OUR_PR")
    if our_is_promo(o["ref"]): gtypes.append("OUR_PROMO_PATTERN")
    if not gtypes: continue
    bc = best_cand(cid)
    s = snk.get(bc["snkrdunk_apparel_id"], {}) if bc else {}
    t1 = (top.get(bc["snkrdunk_apparel_id"], {}).get("t1") if bc else {}) or {}
    rows.append({
        "gap_type": "|".join(gtypes), "source": "OUR_CATALOG",
        "our_card_id_if_any": cid, "our_name": o["name"], "our_jp_ref": o["ref"], "our_rarity": o["rarity"],
        "snkrdunk_apparel_id": (bc["snkrdunk_apparel_id"] if bc else ""),
        "snkrdunk_product_number": s.get("pn",""), "snkrdunk_title": s.get("title",""),
        "snkrdunk_image_url": s.get("img",""),
        "scanner_top1_card_id": t1.get("id",""), "scanner_top1_score": t1.get("score",""),
        "scanner_top5_json": json.dumps((top.get(bc["snkrdunk_apparel_id"],{}).get("t5") if bc else []), ensure_ascii=False),
        "reason": ("매핑됨(검증필요)" if bc else "SNK 후보 없음(소스 필요)"),
        "action": ("VERIFY_MAPPING" if bc else "NEEDS_SNK_SOURCE"),
    })
    seen_our.add(cid)

# ── 2) SNK 프로모인데 우리 등록카드로 못 떨어진 것 = 우리가 없는 프로모(추가 후보) ──
# 같은 product_number 중복 → 최고점 대표 1개
snk_promo = [(aid, m) for aid, m in snk.items() if m["promo"] and not m["en"]]
by_pn = defaultdict(list)
for aid, m in snk_promo:
    t1 = top.get(aid, {}).get("t1") or {}
    by_pn[m["pn"] or aid].append((aid, m, t1.get("score") or 0, t1))
for pn, lst in by_pn.items():
    lst.sort(key=lambda x: -x[2])
    aid, m, score, t1 = lst[0]
    is_reg = t1.get("id") in reg
    # 등록카드로 떨어졌고 번호도 맞으면 이미 커버됨 → 스킵
    if is_reg:
        o = reg[t1["id"]]
        if m["num"] is not None and m["num"] == o["num"]:
            continue  # 정상 매핑된 프로모
        gtype, reason, action = "SNK_PROMO_MISMATCH", "등록카드 매칭됐으나 번호 불일치(오매핑 의심)", "REVIEW_MISMATCH"
    else:
        gtype = "SNK_PROMO_UNMAPPED"
        if score >= HI:
            reason, action = f"우리 카탈로그에 없는 프로모(스캐너 {score})", "ADD_TO_CATALOG"
        else:
            reason, action = f"프로모 의심·저득점({score})", "MANUAL_CHECK"
    rows.append({
        "gap_type": gtype, "source": "SNK_CATALOG",
        "our_card_id_if_any": (t1.get("id") if is_reg else ""), "our_name": (reg[t1["id"]]["name"] if is_reg else ""),
        "our_jp_ref": (reg[t1["id"]]["ref"] if is_reg else ""), "our_rarity": (reg[t1["id"]]["rarity"] if is_reg else ""),
        "snkrdunk_apparel_id": aid, "snkrdunk_product_number": m["pn"], "snkrdunk_title": m["title"],
        "snkrdunk_image_url": m["img"], "scanner_top1_card_id": t1.get("id",""), "scanner_top1_score": t1.get("score",""),
        "scanner_top5_json": json.dumps(top.get(aid,{}).get("t5",[]), ensure_ascii=False),
        "reason": reason, "action": action,
    })

# ── CSV ──
COLS = ["gap_type","source","our_card_id_if_any","our_name","our_jp_ref","our_rarity","snkrdunk_apparel_id",
        "snkrdunk_product_number","snkrdunk_title","snkrdunk_image_url","scanner_top1_card_id","scanner_top1_score",
        "scanner_top5_json","reason","action"]
with open(OUT, "w", newline="", encoding="utf-8") as f:
    w = csv.DictWriter(f, fieldnames=COLS); w.writeheader()
    for r in rows: w.writerow(r)

# ── 요약 ──
ac = Counter(r["action"] for r in rows)
gt = Counter(r["gap_type"].split("|")[0] for r in rows)
nojp = sum(1 for o in reg.values() if not o["set"])
pr = sum(1 for o in reg.values() if o["rarity"]=="PR")
pp = sum(1 for o in reg.values() if our_is_promo(o["ref"]))
snk_promo_total = len(snk_promo)
unmapped = sum(1 for r in rows if r["gap_type"]=="SNK_PROMO_UNMAPPED")
addable = ac.get("ADD_TO_CATALOG",0)
manual = ac.get("MANUAL_CHECK",0)
mismatch = sum(1 for r in rows if r["gap_type"]=="SNK_PROMO_MISMATCH")
print(f"[CSV] {OUT}  (행 {len(rows)})")
print("="*55)
print(f"  우리 NO_JP            : {nojp}")
print(f"  우리 PR               : {pr}")
print(f"  우리 promo-pattern    : {pp}")
print(f"  SNK 프로모(EN제외)    : {snk_promo_total}  · 고유 product {len(by_pn)}")
print(f"  SNK 프로모 미매핑     : {unmapped}  (우리 카탈로그에 없음)")
print(f"   → 추가가능(고득점≥{HI}): {addable}")
print(f"   → 수동확인(저득점)   : {manual}")
print(f"  SNK 프로모 번호불일치 : {mismatch}  (오매핑 의심)")
print(f"  action 분포           : {dict(ac)}")
