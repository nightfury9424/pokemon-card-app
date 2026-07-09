#!/usr/bin/env python3
"""⑥ approved override CSV export (dry-run 산출물만). ★ DB/apply 0 · prod write 0.

review_queue 에서 review_status='APPROVED_REPLACE_WITH_SNK' 만 뽑아
가격선택 레이어(⑦)에 넘길 override CSV + 요약 + 적용전 diff 리포트 생성.
latest_trade_date = SNK RAW sales-chart 최근 거래일(라이브/캐시).
★ 승인된 것만. 보류/거절/매핑오류는 override 에 안 들어감.

사용:
  cd python/price_v8 && \
  /Users/fury/miniconda3/envs/scanner_v2/bin/python -m snk_pipeline.export_override
"""
import csv
import datetime
import json
import os

from . import config, db, snk_client

HERE = os.path.dirname(__file__)
OUT_DIR = os.path.join(HERE, "out")
CHART_CACHE = os.path.join(HERE, "snk_chart_cache.json")

OVERRIDE_COLS = [
    "card_id", "card_name", "current_scrydex_price", "approved_snk_price",
    "diff_krw", "diff_pct", "snk_n", "latest_trade_date", "action",
    "reviewer_decision", "FLAG_THIN_EVIDENCE",
    # 추적용 추가
    "rarity", "collection_number", "snkrdunk_apparel_id", "snk_A_basis",
    "snk_A_n_3m", "ladder_violation", "confidence", "priority",
]


def _latest_raw_trade_date(apparel_id, cache):
    """SNK RAW(opt18) 최근 거래일. 캐시 우선 → 없으면 라이브."""
    key = str(apparel_id)
    if key in cache:
        series = (cache[key].get("series") or {}).get("RAW") or []
        if series:
            ts = max(p[0] for p in series)
            return datetime.datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d")
        raw = cache[key].get("raw") or {}
        if raw.get("last_date"):
            return raw["last_date"]
    pairs = snk_client.chart_pairs(apparel_id, "threeMonths", config.OPT_A) or \
        snk_client.chart_pairs(apparel_id, "oneMonth", config.OPT_A)
    if pairs:
        return datetime.datetime.fromtimestamp(max(t for t, _ in pairs) / 1000).strftime("%Y-%m-%d")
    return ""


def run():
    conn = db.init()
    os.makedirs(OUT_DIR, exist_ok=True)
    cache = {}
    if os.path.exists(CHART_CACHE):
        try:
            cache = json.load(open(CHART_CACHE, encoding="utf-8"))
        except Exception:
            cache = {}

    # 배치 = 최신 run 의 HIGH (이번 사이클). 전체 상태 카운트는 별도.
    run_id = conn.execute("SELECT MAX(run_id) m FROM review_queue").fetchone()["m"]
    all_high = conn.execute(
        "SELECT * FROM review_queue WHERE run_id=? AND priority='HIGH'", (run_id,)).fetchall()
    approved = [r for r in all_high if r["review_status"] == "APPROVED_REPLACE_WITH_SNK"]

    ts = datetime.datetime.now().strftime("%Y%m%d_%H%M")
    override_path = os.path.join(OUT_DIR, f"snk_override_approved_{ts}.csv")
    report_path = os.path.join(OUT_DIR, f"snk_override_report_{ts}.md")

    rows = []
    total_down = 0
    pct_sum = 0.0
    thin_n = 0
    for r in approved:
        cur = r["scrydex_raw_krw"]
        new = r["snk_A_krw"]
        diff = new - cur
        pct = round(diff / cur * 100, 1) if cur else 0
        thin = "true" if (r["snk_A_n"] or 0) < config.MIN_N_REPLACE else "false"
        if thin == "true":
            thin_n += 1
        total_down += diff
        pct_sum += pct
        rows.append({
            "card_id": r["card_id"], "card_name": r["card_name"],
            "current_scrydex_price": cur, "approved_snk_price": new,
            "diff_krw": diff, "diff_pct": pct, "snk_n": r["snk_A_n"],
            "latest_trade_date": _latest_raw_trade_date(r["snkrdunk_apparel_id"], cache),
            "action": "REPLACE_RAW_WITH_SNK_A" if r["priority"] == "HIGH" else "REVIEW",
            "reviewer_decision": f'{r["review_status"]} by {r["reviewed_by"] or "-"} @{r["reviewed_at"] or "-"}',
            "FLAG_THIN_EVIDENCE": thin,
            "rarity": r["rarity"], "collection_number": r["collection_number"],
            "snkrdunk_apparel_id": r["snkrdunk_apparel_id"], "snk_A_basis": r["snk_A_basis"],
            "snk_A_n_3m": r["snk_A_n_3m"], "ladder_violation": r["ladder_violation"],
            "confidence": r["replacement_confidence"], "priority": r["priority"],
        })

    with open(override_path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=OVERRIDE_COLS)
        w.writeheader()
        w.writerows(rows)

    # ── 배치 전체 상태 카운트 (HIGH 10) ──
    cnt = {"APPROVED_REPLACE_WITH_SNK": 0, "REJECTED_KEEP_SCRYDEX": 0,
           "HOLD": 0, "MAPPING_REVIEW": 0, "PENDING_REVIEW": 0}
    for r in all_high:
        cnt[r["review_status"]] = cnt.get(r["review_status"], 0) + 1
    avg_pct = round(pct_sum / len(rows), 1) if rows else 0

    # ── 적용전 diff 리포트 (md) ──
    lines = [
        f"# SNK override 적용전 diff 리포트 (dry-run) — {ts}",
        "",
        f"> ★ **DB/apply 0 · prod write 0.** override CSV = `{os.path.basename(override_path)}`",
        f"> run_id `{run_id}` · 배치 = HIGH 하향 {len(all_high)}장 · 환율 JPY×{config.JPY_KRW}",
        "",
        "## 배치 요약 (HIGH 10)",
        "| 항목 | 값 |",
        "|---|---|",
        f"| 승인(대체) | {cnt['APPROVED_REPLACE_WITH_SNK']} |",
        f"| 거절(scrydex 유지) | {cnt['REJECTED_KEEP_SCRYDEX']} |",
        f"| 보류 | {cnt['HOLD']} |",
        f"| 매핑오류 | {cnt['MAPPING_REVIEW']} |",
        f"| 미검수(PENDING) | {cnt['PENDING_REVIEW']} |",
        f"| **총 하락 금액(승인분)** | **{total_down:,}원** |",
        f"| 평균 하락률(승인분) | {avg_pct}% |",
        f"| ⚠ n<5 얇은근거 카드 | {thin_n} |",
        "",
        "## 승인 카드별 diff (적용 시)",
        "| 카드 | 레어/번호 | 현재(scrydex) | → 승인(SNK) | 변동 | n | 최근거래 | thin |",
        "|---|---|--:|--:|--:|--:|---|:--:|",
    ]
    for d in sorted(rows, key=lambda x: x["diff_pct"]):
        flag = "⚠" if d["FLAG_THIN_EVIDENCE"] == "true" else ""
        lines.append(
            f"| {d['card_name']} | {d['rarity']} {d['collection_number']} | "
            f"{d['current_scrydex_price']:,} | {d['approved_snk_price']:,} | "
            f"{d['diff_pct']}% | {d['snk_n']} | {d['latest_trade_date']} | {flag} |")
    lines += [
        "",
        "## 다음 (미실행)",
        "- ⑦ GlobalPriceService 가격선택 시뮬: 이 override 반영 시 KO 예상가/차트/자산 영향 계산.",
        "- ⑧ 운영 반영 = 별도 세션·백업+승인 후 (price_snapshots source='SNKRDUNK_JP' + override lookup).",
        f"- ⚠ thin {thin_n}장(n<5)은 ⑦ 전에 HOLD 재검토 권장 (현재 FLAG_THIN_EVIDENCE=true).",
    ]
    open(report_path, "w", encoding="utf-8").write("\n".join(lines))

    print(f"[override] 승인 {len(rows)}장 → {override_path}")
    print(f"[override] 배치상태 HIGH10: 승인 {cnt['APPROVED_REPLACE_WITH_SNK']} · 거절 {cnt['REJECTED_KEEP_SCRYDEX']} "
          f"· 보류 {cnt['HOLD']} · 매핑오류 {cnt['MAPPING_REVIEW']} · 미검수 {cnt['PENDING_REVIEW']}")
    print(f"[override] 총 하락 {total_down:,}원 · 평균 {avg_pct}% · ⚠thin(n<5) {thin_n}장")
    print(f"[override] 리포트 → {report_path}")
    print("[override] ★ DB/apply 0 · prod write 0 — 산출물(CSV+MD)만 생성")
    return override_path, report_path


if __name__ == "__main__":
    run()
