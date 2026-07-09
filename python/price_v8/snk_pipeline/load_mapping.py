#!/usr/bin/env python3
"""승인게이트: working mapping → approved_mapping 테이블.

★ working/high-confidence mapping(3,313) ≠ approved.
   매핑 정확성은 사람이 봤으나, 가격 override 용 운영-확정은 아님.
   여기서 명시적 approve 를 거친 APPROVED 만 collector/override 가 사용한다.

사용법:
  python -m snk_pipeline.load_mapping load
      working CSV 전체를 status=WORKING 으로 적재 (이미 있으면 매핑필드만 갱신, status 보존).
  python -m snk_pipeline.load_mapping approve --from-csv <csv> [--col card_id] [--by 사람]
      CSV 의 card_id 목록을 APPROVED 로 승급 (예: HIGH 10 down_first).
  python -m snk_pipeline.load_mapping approve --card-id CRD_xxx [--by 사람]
  python -m snk_pipeline.load_mapping reject  --card-id CRD_xxx [--by 사람] [--note ...]
  python -m snk_pipeline.load_mapping status
      status 별 카운트 + APPROVED 목록.
"""
import argparse
import csv
import datetime

from . import config, db


def _now():
    return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def load(conn):
    rows = list(csv.DictReader(open(config.WORKING_MAPPING_CSV, encoding="utf-8")))
    ins = upd = 0
    now = _now()
    for r in rows:
        cid = r["our_card_id"]
        exists = conn.execute(
            "SELECT mapping_status FROM approved_mapping WHERE card_id=?", (cid,)).fetchone()
        if exists:
            # 매핑 필드만 갱신, 승인 상태는 절대 덮지 않음
            conn.execute(
                """UPDATE approved_mapping SET our_name=?, our_jp_ref=?, our_rarity=?,
                   snkrdunk_apparel_id=?, snk_product_number=?, source_decided_at=?
                   WHERE card_id=?""",
                (r["our_name"], r.get("our_jp_ref", ""), r.get("our_rarity", ""),
                 int(r["snkrdunk_apparel_id"]), r.get("snk_product_number", ""),
                 r.get("decided_at", ""), cid))
            upd += 1
        else:
            conn.execute(
                """INSERT INTO approved_mapping
                   (card_id, our_name, our_jp_ref, our_rarity, snkrdunk_apparel_id,
                    snk_product_number, mapping_status, mapping_confidence,
                    source_decided_at, loaded_at)
                   VALUES (?,?,?,?,?,?, 'WORKING', 'high_confidence', ?, ?)""",
                (cid, r["our_name"], r.get("our_jp_ref", ""), r.get("our_rarity", ""),
                 int(r["snkrdunk_apparel_id"]), r.get("snk_product_number", ""),
                 r.get("decided_at", ""), now))
            ins += 1
    conn.commit()
    print(f"[load] working CSV {len(rows)}행 → 신규 {ins} · 갱신 {upd} (status 보존)")


def _set_status(conn, card_ids, status, by, note):
    now = _now()
    n = 0
    for cid in card_ids:
        cur = conn.execute(
            """UPDATE approved_mapping
               SET mapping_status=?, approved_by=?, approved_at=?,
                   notes=COALESCE(?, notes)
               WHERE card_id=?""",
            (status, by, now, note, cid))
        n += cur.rowcount
    conn.commit()
    missing = len(card_ids) - n
    print(f"[{status}] {n}건 적용" + (f" · {missing}건 미발견(먼저 load 필요)" if missing else ""))


def approve(conn, args):
    ids = _collect_ids(args)
    _set_status(conn, ids, "APPROVED", args.by, args.note)


def reject(conn, args):
    ids = _collect_ids(args)
    _set_status(conn, ids, "REJECTED", args.by, args.note)


def _collect_ids(args):
    if args.card_id:
        return [args.card_id]
    if args.from_csv:
        rows = list(csv.DictReader(open(args.from_csv, encoding="utf-8")))
        return [r[args.col] for r in rows if r.get(args.col)]
    raise SystemExit("--card-id 또는 --from-csv 필요")


def status(conn):
    print("=== approved_mapping status 분포 ===")
    for r in conn.execute(
            "SELECT mapping_status, COUNT(*) c FROM approved_mapping GROUP BY mapping_status ORDER BY c DESC"):
        print(f"  {r['mapping_status']:10} {r['c']}")
    appr = conn.execute(
        """SELECT card_id, our_name, our_rarity, snkrdunk_apparel_id, approved_by, approved_at
           FROM approved_mapping WHERE mapping_status='APPROVED' ORDER BY approved_at""").fetchall()
    print(f"\n=== APPROVED {len(appr)}장 ===")
    for r in appr:
        print(f"  {r['card_id']}  {r['our_name'][:14]:14} {r['our_rarity'] or '':4} "
              f"aid={r['snkrdunk_apparel_id']:<8} by={r['approved_by'] or '-'} @{r['approved_at'] or '-'}")


def main():
    ap = argparse.ArgumentParser(description="SNK approved-mapping 승인게이트")
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("load")
    sub.add_parser("status")
    for name in ("approve", "reject"):
        p = sub.add_parser(name)
        p.add_argument("--card-id")
        p.add_argument("--from-csv")
        p.add_argument("--col", default="card_id")
        p.add_argument("--by", default="operator")
        p.add_argument("--note")
    args = ap.parse_args()

    conn = db.init()
    if args.cmd == "load":
        load(conn)
    elif args.cmd == "status":
        status(conn)
    elif args.cmd == "approve":
        approve(conn, args)
        status(conn)
    elif args.cmd == "reject":
        reject(conn, args)
        status(conn)


if __name__ == "__main__":
    main()
