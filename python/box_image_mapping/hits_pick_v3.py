"""
2026-05-30 도감 힛카드 v3 자동 선정 (사용자 명시 logic).

규칙 (사용자 ultrathink 확정):
  1번: MUR/BWR 무조건 (있으면 — 시리즈 최상위)
  2-3번: 가격 높은 SAR
  4번: 간혹 AR (AR 가격이 다음 SAR 보다 높을 때만, 아니면 SAR 3번째)
  fallback: SAR/AR 부족하면 RR/SSR/UR/HR/CSR/SR 가격순으로 채움 (닌자스피너 같은 신규 시리즈)

입력: hits_priced.md (40 product × top 15)
출력: hits_picks_v3.md (각 시리즈 4장 + 가격)
"""
from __future__ import annotations
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).parent
DEX_JSON = Path("/tmp/dex40.json")
OUT = HERE / "hits_picks_v3.md"

SSH_KEY = "/Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem"
PROD_USER = "ubuntu@52.78.3.120"

RARITY_CASE = """
CASE c.rarity_code
  WHEN 'MUR' THEN 1 WHEN 'BWR' THEN 2 WHEN 'SAR' THEN 3 WHEN 'SSR' THEN 4
  WHEN 'UR'  THEN 5 WHEN 'HR'  THEN 6 WHEN 'CSR' THEN 7 WHEN 'SR'  THEN 8
  WHEN 'AR'  THEN 9 WHEN 'ACE' THEN 10 WHEN 'RRR' THEN 11 WHEN 'RR' THEN 12
  WHEN 'H'   THEN 13 WHEN 'R'  THEN 14 WHEN 'U'   THEN 15 WHEN 'C'  THEN 16
  WHEN 'S'   THEN 17 WHEN 'K'  THEN 18 WHEN 'PR'  THEN 99 ELSE 50
END
"""


def psql_q(sql: str) -> str:
    cmd = ["ssh", "-i", SSH_KEY, PROD_USER,
           f"docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -t -A -F'|' -c \"{sql}\""]
    return subprocess.check_output(cmd, text=True)


def fetch_cards_priced(product_ids: list[str]) -> dict[str, list[dict]]:
    """각 product 의 모든 visible 카드 + KO 가격."""
    ids_in = ",".join(f"'{pid}'" for pid in product_ids)
    sql = f"""
WITH ranked AS (
  SELECT c.product_id, c.card_id, c.name, c.rarity_code, COALESCE(c.collection_number,'') AS col,
         {RARITY_CASE.strip()} AS pri,
         (SELECT price FROM price_snapshots
            WHERE card_id=c.card_id AND source='KO_ESTIMATED'
            ORDER BY traded_at DESC LIMIT 1) AS ko_price
  FROM cards c WHERE c.is_visible=TRUE AND c.language='KO' AND c.product_id IN ({ids_in})
)
SELECT product_id, card_id, name, rarity_code, col, COALESCE(ko_price::text,'')
FROM ranked
""".replace("\n", " ").replace("  ", " ")
    raw = psql_q(sql)
    by_pid: dict[str, list[dict]] = {}
    for line in raw.strip().splitlines():
        if not line.strip(): continue
        parts = line.split("|")
        if len(parts) < 6: continue
        pid, cid, name, rarity, col, price = parts[:6]
        by_pid.setdefault(pid, []).append({
            "card_id": cid, "name": name, "rarity": rarity, "col": col,
            "price": int(price) if price else 0,
        })
    return by_pid


def top_priced(cards: list[dict]) -> dict | None:
    if not cards: return None
    return max(cards, key=lambda x: x["price"])


def pick_hits(cards: list[dict]) -> list[dict]:
    hits: list[dict] = []
    seen_ids: set[str] = set()

    def take(c: dict, reason: str):
        if c and c["card_id"] not in seen_ids:
            c["reason"] = reason
            hits.append(c)
            seen_ids.add(c["card_id"])

    # 1번: MUR/BWR 무조건
    top = [c for c in cards if c["rarity"] in ("MUR", "BWR")]
    if top:
        take(top_priced(top), "MUR/BWR 시리즈 최상위")

    # 2-3번: SAR 가격순 top 2
    sars = sorted([c for c in cards if c["rarity"] == "SAR" and c["card_id"] not in seen_ids],
                  key=lambda x: -x["price"])
    for s in sars[:2]:
        take(s, "SAR 가격순")

    # 4번: AR 가격이 다음 SAR 보다 높으면 AR
    next_sar = sars[2] if len(sars) > 2 else None
    ar_cards = sorted([c for c in cards if c["rarity"] == "AR" and c["card_id"] not in seen_ids],
                      key=lambda x: -x["price"])
    top_ar = ar_cards[0] if ar_cards else None

    if top_ar and (not next_sar or top_ar["price"] >= next_sar["price"]):
        take(top_ar, "AR 가격 > 다음 SAR")
    elif next_sar:
        take(next_sar, "SAR 가격순")

    # fallback: 부족하면 UR/HR/SSR/SR/CSR/RR 가격순으로 채움 (닌자스피너 같은 신규)
    if len(hits) < 4:
        fallback = sorted([c for c in cards
                          if c["rarity"] in ("UR","HR","CSR","SSR","SR","RR")
                          and c["card_id"] not in seen_ids],
                          key=lambda x: -x["price"])
        for c in fallback:
            if len(hits) >= 4: break
            take(c, f"fallback ({c['rarity']} 가격순)")

    return hits[:4]


def main() -> int:
    dex = json.loads(DEX_JSON.read_text())
    products = dex["data"]["products"]
    product_ids = [p["productId"] for p in products]
    by_pid = fetch_cards_priced(product_ids)

    lines = [
        "# 도감 힛카드 v3 — 자동 추출 (사용자 logic)",
        "",
        "**규칙**:",
        "1. MUR/BWR 무조건 1장 (시리즈 최상위)",
        "2-3. 가격 높은 SAR 2장",
        "4. 간혹 AR (AR 가격이 다음 SAR보다 높을 때) — 아니면 SAR 3번째",
        "fallback: SAR 부족하면 RR/UR/HR/SR 가격순 (예: 닌자스피너 KO 미발매 부분)",
        "",
        "각 시리즈 4장. reject 항목 있으면 ❌ + 대체 알려주세요.",
        "",
        "---",
        "",
    ]

    confirmed_map: dict[str, list[dict]] = {}
    for prod in products:
        pid = prod["productId"]
        pname = prod["productName"]
        cards = by_pid.get(pid, [])
        hits = pick_hits(cards)
        confirmed_map[pid] = hits

        lines.append(f"## {pname}")
        lines.append("")
        lines.append(f"- product_id: `{pid}`")
        lines.append(f"- KO {len(cards)}장 / 가격 있는 {sum(1 for c in cards if c['price'])}장")
        lines.append("")
        lines.append("| # | rarity | col# | 카드명 | 가격(원) | card_id | 이유 |")
        lines.append("|---|--------|------|--------|----------|---------|------|")
        for i, h in enumerate(hits, 1):
            price_str = f"{h['price']:,}" if h["price"] else "-"
            lines.append(f"| {i} | {h['rarity']} | {h['col']} | {h['name']} | {price_str} | `{h['card_id']}` | {h['reason']} |")
        lines.append("")

    # JSON 도 같이 저장 (다음 cycle 에서 backend override 적용용).
    json_out = HERE / "hits_picks_v3.json"
    json_out.write_text(json.dumps({
        pid: [h["card_id"] for h in hits] for pid, hits in confirmed_map.items()
    }, ensure_ascii=False, indent=2), encoding="utf-8")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    total = sum(len(h) for h in confirmed_map.values())
    print(f"[ok] {OUT}")
    print(f"     {json_out}")
    print(f"  products: {len(products)} / 힛카드 총 {total}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
