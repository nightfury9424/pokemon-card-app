#!/usr/bin/env python3
"""grail KO 과소 — 증거 산출 (검증용, 산출로직 분리). ★ prod write 0.

GPT 검토(2026-06-30) 반영 — 섞인 로직 전부 분리:
- 현재KO = prod ko_estimation_audit.ko_price 그대로 (재구성 금지).
- selected_raw/source/coef 는 audit 값 그대로 별도 컬럼.
- EN/JP/SNK 후보 raw 각각 별도 컬럼 (컬럼명 EN_raw 고정 금지).
- JP시나리오 = JP_raw × JP계수 (JP_raw 또는 계수 없으면 NA, snk 대용 금지).
- SNK시나리오 = SNK_raw × JP계수 (없으면 NA).
- 계수 없으면 시나리오 계산 안 함 → NA + coef_missing.
- 선택버그(raw)와 과소버그(최종KO) 분리.
- 0원은 실제 0일 때만. 없음/계산불가는 빈값(NA).

입력(전부 로컬, prod read-only 추출본):
  prod_ko_audit_latest.csv  prod_raw_evidence.csv  prod_coefficients.csv  snk_price_full.csv  catalog
출력: out/grail_evidence.csv + out/grail_evidence.html
"""
import csv
import os
from collections import defaultdict

from . import config

HERE = os.path.dirname(__file__)
PV8 = config.PV8
OUT_DIR = os.path.join(HERE, "out")
AUDIT_CSV = os.path.join(HERE, "prod_ko_audit_latest.csv")
RAW_CSV = os.path.join(HERE, "prod_raw_evidence.csv")
COEF_CSV = os.path.join(HERE, "prod_coefficients.csv")
JPY = config.JPY_KRW

ALT_RAW_GATE = 1.5   # 대체 소스 raw가 선택 raw의 1.5배+ 높을 때만 "검토 대상"


def _i(x):
    try:
        return int(float(x))
    except (TypeError, ValueError):
        return 0


def load_prod_raw():
    d = defaultdict(dict)
    for r in csv.DictReader(open(RAW_CSV, encoding="utf-8")):
        cid, src, st, gr = r["card_id"], r["source"], r["card_status"], r["grade"]
        krw = _i(r["price"])
        if src == "SCRYDEX_EN" and st == "RAW":
            d[cid]["en_raw"] = krw
        elif src == "SCRYDEX_JP" and st == "RAW":
            d[cid]["jp_raw"] = krw
        elif src == "SCRYDEX_JP" and st == "GRADED" and gr == "10":
            d[cid]["jp_p10"] = krw
        elif src == "SCRYDEX_JP" and st == "GRADED" and gr == "9":
            d[cid]["jp_p9"] = krw
    return d


def load_snk():
    snk = {}
    for r in csv.DictReader(open(os.path.join(PV8, "snk_price_full.csv"), encoding="utf-8")):
        a1n, a1m, a3n, a3m = _i(r["A1m_n"]), _i(r["A1m_med"]), _i(r["A3m_n"]), _i(r["A3m_med"])
        raw_jpy = a1m if a1n > 0 else (a3m if a3n > 0 else 0)
        p10m = _i(r["PSA10_1m_med"]) if _i(r["PSA10_1m_n"]) > 0 else _i(r["PSA10_3m_med"])
        p9m = _i(r["PSA9_1m_med"]) if _i(r["PSA9_1m_n"]) > 0 else _i(r["PSA9_3m_med"])
        snk[r["card_id"]] = {"raw": round(raw_jpy * JPY), "n": max(a1n, a3n),
                             "p10": round(p10m * JPY), "p9": round(p9m * JPY)}
    return snk


def load_coef():
    card_jp, rarity_jp = {}, {}
    for r in csv.DictReader(open(COEF_CSV, encoding="utf-8")):
        if r["coef_type"] != "JP":
            continue
        try:
            c = float(r["coef"])
        except ValueError:
            continue
        if r["scope"] == "CARD" and r["card_id"]:
            card_jp[r["card_id"]] = c
        elif r["scope"] == "RARITY":
            rarity_jp[r["rarity"]] = c
    return card_jp, rarity_jp


def ladder_order(raw, p10, p9):
    """티어 내림차순 순서 문자열 (정상/비정상 판정은 하지 않음 — 카드군별로 다름)."""
    have = sorted([(n, v) for n, v in (("RAW", raw), ("PSA10", p10), ("PSA9", p9)) if v and v > 0],
                  key=lambda x: -x[1])
    return " > ".join(n for n, _ in have)


def run():
    os.makedirs(OUT_DIR, exist_ok=True)
    prod = load_prod_raw()
    snk = load_snk()
    card_jp, rarity_jp = load_coef()
    cat = {r["card_id"]: r for r in csv.DictReader(open(config.CATALOG_CSV, encoding="utf-8"))}

    rows = []
    for a in csv.DictReader(open(AUDIT_CSV, encoding="utf-8")):
        cid = a["card_id"]
        ko = _i(a["ko_price"])
        if ko <= 0:
            continue
        src = a["selected_source"]
        sel_raw = _i(a["sel_raw_krw"])
        coef_cur = a["coef_value"]
        m = cat.get(cid, {})
        rar = m.get("rarity_code", "")

        P = prod.get(cid, {})
        en_raw, jp_raw = P.get("en_raw", 0), P.get("jp_raw", 0)
        jp_p10, jp_p9 = P.get("jp_p10", 0), P.get("jp_p9", 0)
        S = snk.get(cid, {})
        snk_raw, snk_n, snk_p10, snk_p9 = S.get("raw", 0), S.get("n", 0), S.get("p10", 0), S.get("p9", 0)

        # 검토 대상 게이트: 대체 소스(JP/SNK) raw 가 선택 raw 보다 유의미하게 높을 때
        alt_max = max(jp_raw, snk_raw)
        if not (sel_raw > 0 and alt_max > sel_raw * ALT_RAW_GATE):
            continue

        # ★ 가격 모드: PROMO_DIRECT = JP raw 그대로(계수 미적용). 그 외 = v6 계수.
        is_promo = (src == "PROMO_DIRECT")
        if is_promo:
            pricing_mode, jp_coef_out, jp_coef_scope, coef_missing = "RAW_DIRECT", "", "PROMO", False
            ko_via_jp = jp_raw if jp_raw > 0 else ""       # raw 그대로
            ko_via_snk = snk_raw if snk_raw > 0 else ""    # raw 그대로
        else:
            pricing_mode = "COEF"
            jc = card_jp.get(cid)
            jp_coef_scope = "CARD"
            if jc is None:
                jc = rarity_jp.get(rar)
                jp_coef_scope = "RARITY" if jc is not None else ""
            coef_missing = jc is None
            ko_via_jp = round(jp_raw * jc) if (jp_raw > 0 and jc) else ""
            ko_via_snk = round(snk_raw * jc) if (snk_raw > 0 and jc) else ""
            jp_coef_out = jc if jc is not None else ""
        mult_jp = round(ko_via_jp / ko, 1) if ko_via_jp != "" else ""
        mult_snk = round(ko_via_snk / ko, 1) if ko_via_snk != "" else ""

        # ★ 플래그 — 선택버그(raw)와 과소버그(최종KO) 분리
        selection_bug_raw = (src == "EN" and jp_raw > 0 and en_raw > 0 and jp_raw > en_raw)
        underpriced_by_jp = (ko_via_jp != "" and ko_via_jp > ko)
        underpriced_by_snk = (ko_via_snk != "" and ko_via_snk > ko)
        actionable = underpriced_by_jp or underpriced_by_snk

        if coef_missing:
            category = "COEF_MISSING"           # 고가인데 JP계수 없어 계산불가
        elif actionable:
            category = "UNDERPRICED"             # 최종KO 기준 과소 (실제 후보)
        elif selection_bug_raw:
            category = "SELECTION_ONLY"          # raw는 EN오선택이나 최종KO 과소는 아님
        else:
            category = "REVIEW"                  # 대체 raw 높으나 과소 아님

        rows.append({
            "card_id": cid, "name": m.get("name", ""), "rarity": rar,
            "num": m.get("collection_number", ""), "jp_ref": m.get("jp_scrydex_ref", ""),
            "en_ref": m.get("en_scrydex_ref", ""),
            # 시스템 실제 (audit 그대로)
            "selected_source": src, "ko_current": ko, "selected_raw_krw": sel_raw,
            "coef_current": coef_cur,
            # 후보 raw (각 소스별)
            "en_raw": en_raw, "jp_raw": jp_raw, "snk_raw": snk_raw, "snk_n": snk_n,
            # graded 티어 (scrydex JP vs SNK)
            "jp_p10": jp_p10, "jp_p9": jp_p9, "snk_p10": snk_p10, "snk_p9": snk_p9,
            "scry_ladder": ladder_order(jp_raw, jp_p10, jp_p9),
            "snk_ladder": ladder_order(snk_raw, snk_p10, snk_p9),
            # 가격모드 + JP 계수 + 시나리오 (NA 처리)
            "pricing_mode": pricing_mode, "jp_coef": jp_coef_out, "jp_coef_scope": jp_coef_scope,
            "ko_via_jp": ko_via_jp, "ko_via_snk": ko_via_snk,
            "mult_jp": mult_jp, "mult_snk": mult_snk,
            # 분리된 플래그
            "selection_bug_raw": selection_bug_raw, "underpriced_by_jp": underpriced_by_jp,
            "underpriced_by_snk": underpriced_by_snk, "coef_missing": coef_missing,
            "actionable": actionable, "category": category,
        })

    def sortkey(r):
        mults = [v for v in (r["mult_jp"], r["mult_snk"]) if v != ""]
        return -(max(mults) if mults else 0)
    rows.sort(key=sortkey)

    cols = list(rows[0].keys()) if rows else []
    csv_path = os.path.join(OUT_DIR, "grail_evidence.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    from collections import Counter
    cat_c = Counter(r["category"] for r in rows)
    print(f"[evidence] 검토대상 {len(rows)}장 (대체 raw > 선택 raw ×{ALT_RAW_GATE})")
    for k in ("UNDERPRICED", "COEF_MISSING", "SELECTION_ONLY", "REVIEW"):
        if cat_c.get(k):
            print(f"            {k}: {cat_c[k]}")
    print(f"  selection_bug_raw: {sum(1 for r in rows if r['selection_bug_raw'])} · "
          f"underpriced_by_jp: {sum(1 for r in rows if r['underpriced_by_jp'])} · "
          f"underpriced_by_snk: {sum(1 for r in rows if r['underpriced_by_snk'])}")
    print(f"[evidence] → {csv_path}")
    return csv_path


if __name__ == "__main__":
    run()
