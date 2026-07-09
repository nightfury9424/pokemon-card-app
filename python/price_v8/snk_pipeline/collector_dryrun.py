#!/usr/bin/env python3
"""SNK 일일 수집기 (dry-run). ★ APPROVED 매핑만 수집.

카드당 A(18)/PSA10(22)/PSA9(23) × 1m/3m + detail(usedMinPrice) pull
 → JPY median/latest 추출 → KRW 환산 → snk_snapshot 적재 (로컬 SQLite).
prod DB write 0 · 가격 반영 0. all(-1) 미수집. 403/429 즉시 중단.

사용법:
  python -m snk_pipeline.collector_dryrun [--limit N] [--workers 5]
  python -m snk_pipeline.collector_dryrun --include-working   # 테스트 전용(미승인까지)
"""
import argparse
import datetime
from concurrent.futures import ThreadPoolExecutor

from . import config, db, snk_client


def _dq(a1, a3, p10, p9):
    if a1:
        return "A_1M_OK"
    if a3:
        return "A_3M_FB"
    if p10 or p9:
        return "PSA_ONLY"
    return "A_NO_PTS"


def _krw(jpy):
    return round(jpy * config.JPY_KRW)


def fetch_card(card_id, aid):
    """SNK pull 1장 → snapshot row dict 리스트 반환 (DB 미접촉)."""
    det = snk_client.detail(aid)
    used_min = int(det.get("usedMinPrice", 0) or 0)
    used_cnt = int(det.get("usedListingCount", 0) or 0)

    charts = {
        ("A", "1m"): snk_client.chart(aid, "oneMonth", config.OPT_A),
        ("A", "3m"): snk_client.chart(aid, "threeMonths", config.OPT_A),
        ("PSA10", "1m"): snk_client.chart(aid, "oneMonth", config.OPT_PSA10),
        ("PSA10", "3m"): snk_client.chart(aid, "threeMonths", config.OPT_PSA10),
        ("PSA9", "1m"): snk_client.chart(aid, "oneMonth", config.OPT_PSA9),
        ("PSA9", "3m"): snk_client.chart(aid, "threeMonths", config.OPT_PSA9),
    }
    dq = _dq(charts[("A", "1m")], charts[("A", "3m")],
             charts[("PSA10", "3m")] or charts[("PSA10", "1m")],
             charts[("PSA9", "3m")] or charts[("PSA9", "1m")])

    rows = []
    for (tier, rng), pts in charts.items():
        n = len(pts)
        if n == 0:
            continue
        med, lat = snk_client.median(pts), snk_client.latest(pts)
        # A 는 median+latest 둘 다, PSA 는 median(ladder 참고)만 저장
        bases = (("median", med), ("latest", lat)) if tier == "A" else (("median", med),)
        for basis, jpy in bases:
            rows.append(dict(
                card_id=card_id, snkrdunk_apparel_id=aid, tier=tier, range_label=rng,
                basis=basis, points_count=n, price_jpy=jpy, price_krw=_krw(jpy),
                used_min_price_jpy=used_min, used_listing_count=used_cnt,
                exchange_rate_jpy=config.JPY_KRW, data_quality=dq))
    return rows, dq


def run(limit=None, workers=5, include_working=False):
    conn = db.init()
    statuses = ("APPROVED",) if not include_working else ("APPROVED", "WORKING")
    ph = ",".join("?" * len(statuses))
    q = (f"SELECT card_id, snkrdunk_apparel_id FROM approved_mapping "
         f"WHERE mapping_status IN ({ph}) ORDER BY card_id")
    targets = conn.execute(q, statuses).fetchall()
    if limit:
        targets = targets[:limit]

    if not targets:
        print(f"[collector] 대상 0장 (status IN {statuses}). 먼저 load + approve 필요.")
        if not include_working:
            print("            (테스트만: --include-working 으로 WORKING 까지 수집 가능)")
        return

    run_id = datetime.datetime.now().strftime("run_%Y%m%d_%H%M%S")
    collected_at = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if include_working:
        print("[collector] ⚠ --include-working: 미승인 매핑 포함 (테스트 전용, 운영 금지)")
    print(f"[collector] run={run_id} · 대상 {len(targets)}장 · 환율 JPY×{config.JPY_KRW} "
          f"({config.RATE_AS_OF}) · workers={workers}")

    all_rows = []
    dq_counter = {}
    blocked = [False]

    def work(t):
        if blocked[0]:
            return None
        try:
            rows, dq = fetch_card(t["card_id"], t["snkrdunk_apparel_id"])
        except snk_client.SnkBlocked as e:
            blocked[0] = True
            print(f"[collector] ★ 차단(403) 감지 — 중단: {e}")
            return None
        return rows, dq, t["card_id"]

    with ThreadPoolExecutor(max_workers=workers) as ex:
        for res in ex.map(work, targets):
            if not res:
                continue
            rows, dq, _cid = res
            all_rows.extend(rows)
            dq_counter[dq] = dq_counter.get(dq, 0) + 1

    # 단일 스레드 일괄 insert (sqlite 안전)
    ins = 0
    for r in all_rows:
        conn.execute(
            """INSERT OR REPLACE INTO snk_snapshot
               (card_id, snkrdunk_apparel_id, source, tier, range_label, basis,
                points_count, price_jpy, price_krw, used_min_price_jpy,
                used_listing_count, exchange_rate_jpy, data_quality, collected_at, run_id)
               VALUES (?,?, 'SNKRDUNK_JP', ?,?,?,?,?,?,?,?,?,?,?,?)""",
            (r["card_id"], r["snkrdunk_apparel_id"], r["tier"], r["range_label"],
             r["basis"], r["points_count"], r["price_jpy"], r["price_krw"],
             r["used_min_price_jpy"], r["used_listing_count"], r["exchange_rate_jpy"],
             r["data_quality"], collected_at, run_id))
        ins += 1
    conn.commit()

    print(f"[collector] snapshot {ins}행 적재 · 카드 데이터품질 분포:")
    for k in ("A_1M_OK", "A_3M_FB", "PSA_ONLY", "A_NO_PTS"):
        if dq_counter.get(k):
            print(f"             {k}: {dq_counter[k]}")
    if blocked[0]:
        print("[collector] ⚠ 차단으로 일부만 수집 — 같은 명령 재실행 시 이어서 가능(run_id 새로 생성).")
    print(f"[collector] run_id={run_id}  → 다음: detector_dryrun --run-id {run_id}")
    return run_id


def main():
    ap = argparse.ArgumentParser(description="SNK 일일 수집기 dry-run (approved 만)")
    ap.add_argument("--limit", type=int)
    ap.add_argument("--workers", type=int, default=5)
    ap.add_argument("--include-working", action="store_true",
                    help="테스트 전용: 미승인 WORKING 매핑까지 수집")
    args = ap.parse_args()
    run(limit=args.limit, workers=args.workers, include_working=args.include_working)


if __name__ == "__main__":
    main()
