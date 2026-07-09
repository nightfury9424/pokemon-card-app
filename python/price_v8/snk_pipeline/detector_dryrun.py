#!/usr/bin/env python3
"""이상치 디텍터 (dry-run). snk_snapshot vs scrydex JP ladder → review_queue.

정상 ladder = PSA10 > PSA9 > RAW (데이터 84%). 위반/발산만 검수 큐로.
임계·action·confidence 는 분석 단계(build_ladder_anomalies + build_strong_replace)와 동일.
자동 적용 0 — 전부 PENDING_REVIEW. prod write 0.

사용법:
  python -m snk_pipeline.detector_dryrun [--run-id run_xxx]   # 생략 시 최신 run
"""
import argparse
import csv
import datetime

from . import config, db


def load_scrydex_ladder():
    """card_id → {RAW/PSA10/PSA9: med30_krw}. scrydex_jp_ladder_prod.csv (이미 KRW)."""
    lad = {}
    for r in csv.reader(open(config.SCRYDEX_LADDER_CSV, encoding="utf-8")):
        if len(r) < 5 or not r[0].startswith("CRD_"):
            continue
        try:
            lad.setdefault(r[0], {})[r[1]] = float(r[3])  # [3]=med30
        except ValueError:
            pass
    return lad


def load_catalog():
    try:
        return {r["card_id"]: r for r in csv.DictReader(open(config.CATALOG_CSV, encoding="utf-8"))}
    except FileNotFoundError:
        return {}


def snk_A_for_run(conn, run_id):
    """run_id 의 카드별 SNK A 선택값: A_1M median → A_3M median fallback.
    ★ snk_n = 선택한 basis 윈도우의 거래수(값과 동일 윈도우 — 가격 검수 정직성).
       3m 카운트는 참고로 별도 반환.
    반환 card_id → (basis, snk_krw, snk_n, snk_n_3m, apparel_id)."""
    rows = conn.execute(
        """SELECT card_id, snkrdunk_apparel_id, range_label, points_count, price_krw
           FROM snk_snapshot
           WHERE run_id=? AND tier='A' AND basis='median'""", (run_id,)).fetchall()
    agg = {}
    for r in rows:
        d = agg.setdefault(r["card_id"], {"aid": r["snkrdunk_apparel_id"]})
        d[r["range_label"]] = (r["points_count"], r["price_krw"])
    out = {}
    for cid, d in agg.items():
        n1, k1 = d.get("1m", (0, 0))
        n3, k3 = d.get("3m", (0, 0))
        if n1 > 0:
            basis, snk_krw, snk_n = "A_1M", k1, n1
        elif n3 > 0:
            basis, snk_krw, snk_n = "A_3M", k3, n3
        else:
            basis, snk_krw, snk_n = "NONE", 0, 0
        out[cid] = (basis, snk_krw, snk_n, n3, d["aid"])
    return out


def evaluate(raw, p10, p9, snk_krw, snk_basis, snk_n):
    """위반 리스트 + action_status + confidence + priority + floor 반환."""
    c = config
    viol = []
    if p10 and p9 and p10 < p9 * c.TH_GRADED_INVERSION:
        viol.append("GRADED_INVERSION")
    if p10 and raw > p10 * c.TH_RAW_OVER_PSA10:
        viol.append("RAW_OVER_PSA10")
    if p9 and raw > p9 * c.TH_RAW_OVER_PSA9:
        viol.append("RAW_OVER_PSA9")
    if (p10 and p10 / raw >= c.TH_PSA10_STALE) or (p9 and p9 / raw >= c.TH_PSA9_STALE):
        viol.append("RAW_STALE_LOW")
    ratio = round(raw / snk_krw, 3) if snk_krw > 0 else None
    if snk_krw > 0:
        if raw / snk_krw >= c.TH_SNK_DIV_HIGH:
            viol.append("SNK_DIVERGENCE_HIGH")
        elif raw / snk_krw <= c.TH_SNK_DIV_LOW:
            viol.append("SNK_DIVERGENCE_LOW")

    mapping_suspect = bool(snk_krw > 0 and (raw / snk_krw >= c.TH_MAPPING_REVIEW
                                            or raw / snk_krw <= 1 / c.TH_MAPPING_REVIEW))
    if mapping_suspect:
        action = "MAPPING_REVIEW"
    elif snk_basis in ("A_1M", "A_3M") and snk_n >= c.MIN_N_REPLACE:
        action = "REPLACE_WITH_SNK_A"
    elif snk_basis in ("A_1M", "A_3M") and snk_n < c.MIN_N_REPLACE:
        action = "REVIEW_SNK_THIN"
    else:
        action = "KEEP_SCRYDEX"

    vset = set(viol)
    div = "SNK_DIVERGENCE_HIGH" in vset or "SNK_DIVERGENCE_LOW" in vset
    floor = snk_krw > 0 and snk_krw <= c.SNK_FLOOR_KRW
    if action == "MAPPING_REVIEW":
        conf = "MAPPING_REVIEW"
    elif div and snk_n >= c.MIN_N_REPLACE and not floor:
        conf = "STRONG_REPLACE"
    elif div and (snk_n < c.MIN_N_REPLACE or floor):
        conf = "REVIEW_REPLACE"
    elif vset == {"RAW_STALE_LOW"}:
        conf = "LADDER_INFO_ONLY"
    else:
        conf = "KEEP"

    if "SNK_DIVERGENCE_HIGH" in vset:
        prio = "HIGH"          # scrydex 과대 → 하향, 저위험, 먼저
    elif "SNK_DIVERGENCE_LOW" in vset:
        prio = "LOW"           # scrydex 과소 → 상향, 고위험
    else:
        prio = "NONE"
    return viol, action, conf, prio, ("Y" if floor else ""), ratio


def run(run_id=None):
    conn = db.init()
    if not run_id:
        row = conn.execute("SELECT MAX(run_id) m FROM snk_snapshot").fetchone()
        run_id = row["m"] if row else None
    if not run_id:
        print("[detector] snk_snapshot 비어있음 — 먼저 collector_dryrun 실행 필요.")
        return
    print(f"[detector] run_id={run_id}")

    ladder = load_scrydex_ladder()
    catalog = load_catalog()
    snk = snk_A_for_run(conn, run_id)
    print(f"[detector] SNK 카드 {len(snk)} · scrydex ladder {len(ladder)} 카드")

    detected_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    # 같은 run 재실행 idempotent
    conn.execute("DELETE FROM review_queue WHERE run_id=?", (run_id,))

    queued = 0
    no_raw = 0
    from collections import Counter
    prio_c, conf_c = Counter(), Counter()

    for cid, (basis, snk_krw, snk_n, snk_n_3m, aid) in snk.items():
        t = ladder.get(cid, {})
        raw = t.get("RAW")
        if not raw or raw <= 0:
            no_raw += 1
            continue
        p10, p9 = t.get("PSA10"), t.get("PSA9")
        viol, action, conf, prio, floor, ratio = evaluate(raw, p10, p9, snk_krw, basis, snk_n)
        if not viol:
            continue  # 이상 없음 → scrydex 유지(큐 미적재)
        m = catalog.get(cid, {})
        conn.execute(
            """INSERT INTO review_queue
               (run_id, card_id, card_name, rarity, collection_number, snkrdunk_apparel_id,
                scrydex_raw_krw, scrydex_psa10_krw, scrydex_psa9_krw,
                snk_A_krw, snk_A_basis, snk_A_n, snk_A_n_3m, scrydex_raw_to_snk_A_ratio,
                ladder_violation, action_status, replacement_confidence, priority,
                floor_suspect, review_status, detected_at)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?, 'PENDING_REVIEW', ?)""",
            (run_id, cid, m.get("name", ""), m.get("rarity_code", ""),
             m.get("collection_number", ""), aid,
             round(raw), round(p10) if p10 else None, round(p9) if p9 else None,
             snk_krw, basis, snk_n, snk_n_3m, ratio, ";".join(viol), action, conf, prio,
             floor, detected_at))
        queued += 1
        prio_c[prio] += 1
        conf_c[conf] += 1
    conn.commit()

    print(f"[detector] 검수 큐 적재 {queued}장 (이상치) · scrydex RAW 없음 {no_raw}장 건너뜀")
    print("  priority:   " + " · ".join(f"{k}={prio_c[k]}" for k in ("HIGH", "LOW", "NONE") if prio_c[k]))
    print("  confidence: " + " · ".join(f"{k}={v}" for k, v in conf_c.most_common()))
    print(f"\n  ★ HIGH(하향·저위험) 먼저 검수. LOW(상향·고위험)는 n≥10+이미지/세트/번호일치 강한기준.")
    # HIGH STRONG TOP
    top = conn.execute(
        """SELECT card_name, rarity, scrydex_raw_krw, snk_A_krw, scrydex_raw_to_snk_A_ratio,
                  snk_A_n, ladder_violation
           FROM review_queue WHERE run_id=? AND priority='HIGH' AND replacement_confidence='STRONG_REPLACE'
           ORDER BY scrydex_raw_to_snk_A_ratio DESC LIMIT 15""", (run_id,)).fetchall()
    if top:
        print(f"\n  === HIGH · STRONG_REPLACE TOP {len(top)} (발산 큰 순) ===")
        for r in top:
            print(f"    {(r['card_name'] or '')[:14]:14} {r['rarity'] or '':4} "
                  f"raw₩{r['scrydex_raw_krw']:>8,} → SNK_A₩{r['snk_A_krw']:>8,} "
                  f"x{r['scrydex_raw_to_snk_A_ratio']:<5} n={r['snk_A_n']:>2} [{r['ladder_violation']}]")
    return run_id


def main():
    ap = argparse.ArgumentParser(description="SNK 이상치 디텍터 dry-run")
    ap.add_argument("--run-id")
    args = ap.parse_args()
    run(run_id=args.run_id)


if __name__ == "__main__":
    main()
