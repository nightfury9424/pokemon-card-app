#!/usr/bin/env python3
"""grail/체이스 KO 과소평가 디텍터 (dry-run · 로컬). ★ prod write 0.

레시라무 SR 055/053 류 = JP ladder 깨짐 → JP 불신 → EN fallback → en계수×0.1 → KO 60배 과소.
HIGH 10(scrydex 과대→하향)과 정반대. LOW 62에도 안 잡히는 사각지대(JP RAW med30 빈 카드) 포함.

입력(전부 로컬):
  prod_ko_audit_latest.csv       prod read-only 추출 (ko_price/selected_source/coef)
  scrydex_jp_ladder_prod.csv     scrydex JP RAW/PSA10/PSA9 (KRW)
  snk_price_full.csv             SNK 일본 실거래 (JPY)
  prod_cards_full_20260620.csv   카탈로그 (이름/refs/rarity)

출력: out/grail_underpriced_candidates.csv + out/grail_underpriced_report.md
"""
import csv
import os
from collections import defaultdict

from . import config

HERE = os.path.dirname(__file__)
PV8 = config.PV8
OUT_DIR = os.path.join(HERE, "out")
AUDIT_CSV = os.path.join(HERE, "prod_ko_audit_latest.csv")

JPY = config.JPY_KRW

# 임계
MIN_VALUE_KRW = 100_000      # "고가 카드" 하한 (진짜 RAW 추정값)
MAX_KO_FRACTION = 0.40       # KO가 진짜값의 40% 미만 = 과소 (under_x ≥ 2.5)
PSA10_HIGH_KRW = 500_000     # graded만으로도 고가 판정
PSA10_IMPLIED_RAW = 0.15     # RAW 없을 때 PSA10×0.15 = 보수적 raw 하한


def _f(x):
    try:
        return float(x)
    except (TypeError, ValueError):
        return 0.0


def _i(x):
    try:
        return int(float(x))
    except (TypeError, ValueError):
        return 0


def load_ladder():
    lad = defaultdict(dict)
    for r in csv.reader(open(os.path.join(PV8, "scrydex_jp_ladder_prod.csv"), encoding="utf-8")):
        if len(r) < 5 or not r[0].startswith("CRD_"):
            continue
        med, latest, n = _f(r[3]), _f(r[2]), _i(r[4])
        lad[r[0]][r[1]] = {"med": med, "latest": latest, "n": n}
    return lad


def load_snk():
    snk = {}
    p = os.path.join(PV8, "snk_price_full.csv")
    for r in csv.DictReader(open(p, encoding="utf-8")):
        a1n, a1m, a3n, a3m = _i(r["A1m_n"]), _i(r["A1m_med"]), _i(r["A3m_n"]), _i(r["A3m_med"])
        raw_jpy = a1m if a1n > 0 else (a3m if a3n > 0 else 0)
        p10n = _i(r["PSA10_1m_n"]) or _i(r["PSA10_3m_n"])
        p10m = _i(r["PSA10_1m_med"]) if _i(r["PSA10_1m_n"]) > 0 else _i(r["PSA10_3m_med"])
        snk[r["card_id"]] = {
            "raw_krw": round(raw_jpy * JPY), "n": max(a1n, a3n),
            "psa10_krw": round(p10m * JPY), "psa10_n": p10n,
            "apparel": r["snkrdunk_apparel_id"],
        }
    return snk


def load_catalog():
    cat = {}
    for r in csv.DictReader(open(config.CATALOG_CSV, encoding="utf-8")):
        cat[r["card_id"]] = r
    return cat


def run():
    os.makedirs(OUT_DIR, exist_ok=True)
    lad, snk, cat = load_ladder(), load_snk(), load_catalog()

    rows = []
    for a in csv.DictReader(open(AUDIT_CSV, encoding="utf-8")):
        cid = a["card_id"]
        ko = _i(a["ko_price"])
        if ko <= 0:
            continue
        src = a["selected_source"]
        m = cat.get(cid, {})
        jp_ref = (m.get("jp_scrydex_ref") or "")
        has_jp = bool(jp_ref) and jp_ref != "NO_JP"

        L = lad.get(cid, {})
        jp_raw = L.get("RAW", {}).get("med") or L.get("RAW", {}).get("latest") or 0
        jp_raw_n = L.get("RAW", {}).get("n", 0)
        jp_p10 = L.get("PSA10", {}).get("med") or 0
        jp_p9 = L.get("PSA9", {}).get("med") or 0

        S = snk.get(cid, {})
        snk_raw, snk_n = S.get("raw_krw", 0), S.get("n", 0)
        snk_p10 = S.get("psa10_krw", 0)

        # 진짜 RAW 추정값: SNK 실거래 우선 → scrydex JP RAW → PSA10×0.15
        if snk_raw > 0 and snk_n >= 1:
            strong, basis = snk_raw, f"SNK_RAW(n{snk_n})"
        elif jp_raw > 0:
            strong, basis = jp_raw, "SCRYDEX_JP_RAW"
        elif jp_p10 >= PSA10_HIGH_KRW or snk_p10 >= PSA10_HIGH_KRW:
            strong = max(jp_p10, snk_p10) * PSA10_IMPLIED_RAW
            basis = "PSA10x0.15"
        else:
            continue

        if strong < MIN_VALUE_KRW:
            continue
        if ko >= strong * MAX_KO_FRACTION:
            continue  # 과소 아님

        under_x = round(strong / ko, 1)
        ladder_broken = []
        if jp_raw and jp_p9 and jp_raw > jp_p9:
            ladder_broken.append("RAW_OVER_PSA9")
        if jp_raw and jp_p10 and jp_raw > jp_p10:
            ladder_broken.append("RAW_OVER_PSA10")
        if jp_p10 and jp_p9 and jp_p10 < jp_p9:
            ladder_broken.append("GRADED_INVERSION")
        blind_spot = (jp_raw_n == 0)        # scrydex RAW med30 빔 → LOW 62 누락
        en_fallback = (src == "EN" and has_jp)

        sev = ("CRITICAL" if under_x >= 10 else "HIGH" if under_x >= 4 else "MED")
        snk_q = ("SNK_CONFIRMED" if snk_n >= 5 else "SNK_THIN" if snk_n >= 1 else "NO_SNK")

        rows.append({
            "card_id": cid, "name": m.get("name", ""), "rarity": m.get("rarity_code", ""),
            "collection_number": m.get("collection_number", ""),
            "jp_ref": jp_ref, "en_ref": m.get("en_scrydex_ref", ""),
            "ko_price": ko, "selected_source": src, "coef_key": a["coef_key"],
            "coef_value": a["coef_value"], "en_raw_krw": _i(a["sel_raw_krw"]),
            "true_raw_estimate_krw": round(strong), "estimate_basis": basis,
            "under_x": under_x, "severity": sev,
            "snk_raw_krw": snk_raw, "snk_n": snk_n, "snk_psa10_krw": snk_p10,
            "jp_raw_krw": round(jp_raw), "jp_psa10_krw": round(jp_p10), "jp_psa9_krw": round(jp_p9),
            "ladder_broken": ";".join(ladder_broken), "blind_spot_low62": "Y" if blind_spot else "",
            "en_fallback": "Y" if en_fallback else "", "snk_quality": snk_q,
        })

    rows.sort(key=lambda r: -r["under_x"])
    cols = list(rows[0].keys()) if rows else []
    out_csv = os.path.join(OUT_DIR, "grail_underpriced_candidates.csv")
    with open(out_csv, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)

    # 요약
    from collections import Counter
    sev_c = Counter(r["severity"] for r in rows)
    enf = sum(1 for r in rows if r["en_fallback"] == "Y")
    blind = sum(1 for r in rows if r["blind_spot_low62"] == "Y")
    snkc = sum(1 for r in rows if r["snk_quality"] == "SNK_CONFIRMED")
    ladbr = sum(1 for r in rows if r["ladder_broken"])

    rep = [
        "# grail 과소평가 디텍터 (dry-run) — prod write 0",
        "",
        f"입력: prod_ko_audit_latest.csv(3,887) + scrydex JP ladder + SNK 실거래. 환율 JPY×{JPY}.",
        f"조건: 진짜RAW추정 ≥ ₩{MIN_VALUE_KRW:,} · KO < 추정 × {MAX_KO_FRACTION} (= {1/MAX_KO_FRACTION:.1f}배+ 과소)",
        "",
        f"## 검거 {len(rows)}장",
        f"- CRITICAL(≥10x) {sev_c['CRITICAL']} · HIGH(4~10x) {sev_c['HIGH']} · MED(2.5~4x) {sev_c['MED']}",
        f"- EN fallback {enf} · ladder 깨짐 {ladbr} · LOW62 사각지대(RAW med30 빔) {blind} · SNK 실거래 확인 {snkc}",
        "",
        "## TOP 30 (과소 배율 큰 순)",
        "| 카드 | 레어/번호 | KO현재 | 진짜RAW추정 | 배율 | 소스/계수 | SNK | ladder | 비고 |",
        "|---|---|--:|--:|--:|---|--:|---|---|",
    ]
    for r in rows[:30]:
        rep.append(
            f"| {r['name']} | {r['rarity']} {r['collection_number']} | {r['ko_price']:,} | "
            f"{r['true_raw_estimate_krw']:,} ({r['estimate_basis']}) | {r['under_x']}x | "
            f"{r['selected_source']}/{r['coef_value']} | {r['snk_raw_krw']:,}(n{r['snk_n']}) | "
            f"{r['ladder_broken'] or '-'} | {('EN새' if r['en_fallback'] else '')}{' 사각' if r['blind_spot_low62'] else ''} |")
    rep += [
        "",
        "## 다음 (미실행 · 별도 승인)",
        "- SNK_CONFIRMED(n≥5) 부터 검수 UI 상향 트랙으로 → 진짜값 확정.",
        "- SNK 없는 grail = iconic floor table(사람-입력) 또는 scrydex JP RAW.",
        "- 근본수정 = v8 JP-sanity-first(JP깨짐+고가 → MANUAL_REVIEW, ≠EN). 운영반영은 백업+승인 후.",
    ]
    open(os.path.join(OUT_DIR, "grail_underpriced_report.md"), "w", encoding="utf-8").write("\n".join(rep))

    print(f"[grail] 검거 {len(rows)}장 → {out_csv}")
    print(f"[grail] CRITICAL {sev_c['CRITICAL']} · HIGH {sev_c['HIGH']} · MED {sev_c['MED']}")
    print(f"[grail] EN fallback {enf} · ladder깨짐 {ladbr} · LOW62사각지대 {blind} · SNK확인 {snkc}")
    print("[grail] TOP 12:")
    for r in rows[:12]:
        print(f"  {r['name'][:13]:13} {r['rarity']:4} {r['collection_number']:8} "
              f"KO {r['ko_price']:>7,} → 추정 {r['true_raw_estimate_krw']:>9,} "
              f"({r['under_x']}x) [{r['selected_source']}/{r['coef_value']}] "
              f"SNK n{r['snk_n']} {r['ladder_broken']}")
    return out_csv


if __name__ == "__main__":
    run()
