#!/usr/bin/env python3
"""grail 증거를 검증용 표(markdown + clean CSV)로 export → ~/Downloads.
★ GPT 검토 반영: 현재KO=audit값 / 컬럼명 selected_raw / EN·JP·SNK 후보 분리 /
  시나리오 NA 처리 / 선택버그·과소버그 분리 / ladder 일괄정상규칙 제거.
"""
import csv
import os

HERE = os.path.dirname(__file__)
SRC = os.path.join(HERE, "out", "grail_evidence.csv")
DL = os.path.expanduser("~/Downloads")

COLS = [
    ("카드", "name"), ("레어", "rarity"), ("번호", "num"),
    ("분류", "category"), ("가격모드", "pricing_mode"),
    ("시스템선택", "selected_source"), ("현재KO(audit)", "ko_current"),
    ("선택raw(audit)", "selected_raw_krw"), ("현재계수(audit)", "coef_current"),
    ("EN_raw", "en_raw"), ("JP_raw", "jp_raw"), ("SNK_raw", "snk_raw"), ("SNK_n", "snk_n"),
    ("JP계수", "jp_coef"),
    ("JP시나리오=JP_raw×JP계수", "ko_via_jp"), ("배율_JP", "mult_jp"),
    ("SNK시나리오=SNK_raw×JP계수", "ko_via_snk"), ("배율_SNK", "mult_snk"),
    ("scrydex_PSA10", "jp_p10"), ("SNK_PSA10", "snk_p10"),
    ("scrydex_PSA9", "jp_p9"), ("SNK_PSA9", "snk_p9"),
    ("scrydex순서", "scry_ladder"), ("SNK순서", "snk_ladder"),
    ("선택버그_raw", "selection_bug_raw"), ("과소_JP", "underpriced_by_jp"),
    ("과소_SNK", "underpriced_by_snk"), ("계수없음", "coef_missing"),
]
NUMERIC = {"ko_current", "selected_raw_krw", "en_raw", "jp_raw", "snk_raw",
           "ko_via_jp", "ko_via_snk", "jp_p10", "snk_p10", "jp_p9", "snk_p9"}
CAT_RANK = {"UNDERPRICED": 0, "COEF_MISSING": 1, "SELECTION_ONLY": 2, "REVIEW": 3}


def _num(v):
    if v == "" or v is None:
        return "NA"
    try:
        return f"{int(float(v)):,}"
    except (TypeError, ValueError):
        return v


def _cell(v, k):
    if k in NUMERIC:
        return _num(v)
    if v == "":
        return "NA"
    return v


def run():
    rows = list(csv.DictReader(open(SRC, encoding="utf-8")))

    def mx(r):
        m = [float(v) for v in (r["mult_jp"], r["mult_snk"]) if v != ""]
        return max(m) if m else 0
    rows.sort(key=lambda r: (CAT_RANK.get(r["category"], 9), -mx(r)))

    csv_path = os.path.join(DL, "grail_table_20260630.csv")
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.writer(f)
        w.writerow([h for h, _ in COLS])
        for r in rows:
            w.writerow([(r.get(k, "") if r.get(k, "") != "" else "NA") for _, k in COLS])

    from collections import Counter
    cat_c = Counter(r["category"] for r in rows)
    md = [
        "# Grail KO 과소 — 검증용 표 (2026-06-30, 산출로직 분리판)",
        "",
        "prod read-only 추출. **현재KO는 ko_estimation_audit.ko_price 실제값**(재구성 아님).",
        "",
        "## 검산 공식",
        "- **★가격모드(pricing_mode)**: `COEF`=일반(raw×JP계수) / `RAW_DIRECT`=**프로모(PROMO_DIRECT)는 JP raw 그대로, 계수 미적용**.",
        "- **현재KO** = prod audit 실제값.",
        "- **JP시나리오** = COEF면 `JP_raw × JP계수`, RAW_DIRECT(프로모)면 `JP_raw 그대로`. JP_raw/계수 없으면 **NA**(snk 대용 안 함).",
        "- **SNK시나리오** = COEF면 `SNK_raw × JP계수`, RAW_DIRECT(프로모)면 `SNK_raw 그대로`. 없으면 **NA**.",
        "- JP계수 = RARITY-scope JP 계수 (SR 0.388629, AR 0.535789, SAR 0.376892, UR 0.491811, HR 0.432255, PR 0.085544 …). card-scope 있으면 우선.",
        "- 배율_JP = JP시나리오 ÷ 현재KO. 배율_SNK = SNK시나리오 ÷ 현재KO. 시나리오 NA면 배율 NA.",
        "- 가격 KRW. `NA`=데이터/계수 없음(0 아님). `0`은 실제 0일 때만.",
        "- **ladder 순서는 그냥 내림차순 표기**(정상/비정상 판정 안 함). grail/체이스는 PSA10>RAW>PSA9 가능, 일반카드는 PSA10>PSA9>RAW 자연스러움 — 카드군별로 다름.",
        "",
        "## 분류(category)",
        "- **UNDERPRICED**: 과소_JP 또는 과소_SNK = True (최종 v6 KO 기준 실제 과소후보) — 이것만 actionable.",
        "- **COEF_MISSING**: 대체 raw 높은데 JP계수 없어 시나리오 계산불가 (검토필요).",
        "- **SELECTION_ONLY**: raw는 EN오선택(JP_raw>EN_raw)이나 최종KO 과소는 아님 — actionable 아님.",
        "- **REVIEW**: 대체 raw 높으나 과소 아님.",
        "",
        "## 플래그 정의 (선택버그 ≠ 과소버그)",
        "- 선택버그_raw = selected_source='EN' AND JP_raw > EN_raw (raw 레벨).",
        "- 과소_JP = JP시나리오 > 현재KO (최종 KO 레벨).",
        "- 과소_SNK = SNK시나리오 > 현재KO.",
        "",
        f"## 표 ({len(rows)}장 = 대체raw>선택raw×1.5 · 분류→배율 순) "
        f"| UNDERPRICED {cat_c['UNDERPRICED']} · COEF_MISSING {cat_c['COEF_MISSING']} · "
        f"SELECTION_ONLY {cat_c['SELECTION_ONLY']} · REVIEW {cat_c['REVIEW']}",
        "",
        "| " + " | ".join(h for h, _ in COLS) + " |",
        "|" + "|".join("---" for _ in COLS) + "|",
    ]
    for r in rows:
        md.append("| " + " | ".join(_cell(r.get(k, ""), k) for _, k in COLS) + " |")
    md_path = os.path.join(DL, "grail_table_20260630.md")
    open(md_path, "w", encoding="utf-8").write("\n".join(md))

    print(f"[table] {len(rows)}장 · 분류 {dict(cat_c)}")
    print(f"[table] CSV → {csv_path}")
    print(f"[table] MD  → {md_path}")
    print("\n[검산 샘플] UNDERPRICED 상위 3:")
    for r in [x for x in rows if x["category"] == "UNDERPRICED"][:3]:
        jp = f"{float(r['jp_raw']):,.0f}×{r['jp_coef']}={float(r['ko_via_jp']):,.0f}" if r["ko_via_jp"] else "NA"
        sk = f"{float(r['snk_raw']):,.0f}×{r['jp_coef']}={float(r['ko_via_snk']):,.0f}" if r["ko_via_snk"] else "NA"
        print(f"  {r['name']}({r['selected_source']}) 현재 {float(r['ko_current']):,.0f} | JP {jp} | SNK {sk}")
    return csv_path, md_path


if __name__ == "__main__":
    run()
