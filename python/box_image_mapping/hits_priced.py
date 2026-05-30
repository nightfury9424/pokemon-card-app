"""
2026-05-30 도감 힛카드 — 가격 포함 후보 추출.

기존 hits_candidates.py (rarity priority + collection_number) → 가격 신호 빠짐.
이번엔 price_snapshots 의 source='KO_ESTIMATED' 최신값 LATERAL JOIN.

대상: /api/assets/dex?limit=40 의 40 products
각 product 별 top 15 카드 — 가격 desc + rarity rank 보조.

출력: hits_priced.md (사용자 최종 4장 선정 기준)
"""
from __future__ import annotations
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).parent
DEX_JSON = Path("/tmp/dex40.json")
OUT = HERE / "hits_priced.md"

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
    cmd = [
        "ssh", "-i", SSH_KEY, PROD_USER,
        f"docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -t -A -F'|' -c \"{sql}\""
    ]
    return subprocess.check_output(cmd, text=True)


def main() -> int:
    dex = json.loads(DEX_JSON.read_text())
    products = dex["data"]["products"]
    product_ids = [p["productId"] for p in products]
    ids_in = ",".join(f"'{pid}'" for pid in product_ids)

    sql = f"""
WITH ranked AS (
  SELECT c.product_id, c.card_id, c.name, c.rarity_code,
         COALESCE(c.collection_number, '') AS col,
         {RARITY_CASE.strip()} AS pri,
         (SELECT price FROM price_snapshots
            WHERE card_id = c.card_id AND source = 'KO_ESTIMATED'
            ORDER BY traded_at DESC LIMIT 1) AS ko_price,
         (SELECT source FROM price_snapshots
            WHERE card_id = c.card_id AND source = 'KO_ESTIMATED'
            ORDER BY traded_at DESC LIMIT 1) AS ko_source
  FROM cards c
  WHERE c.is_visible=TRUE AND c.language='KO'
    AND c.product_id IN ({ids_in})
),
price_ranked AS (
  SELECT *,
    ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY ko_price DESC NULLS LAST, pri, col, card_id) AS price_rank,
    ROW_NUMBER() OVER (PARTITION BY product_id ORDER BY pri, col, card_id) AS rarity_rank
  FROM ranked
)
SELECT product_id, card_id, name, rarity_code, col, COALESCE(ko_price::text, ''),
       COALESCE(ko_source, ''), price_rank, rarity_rank
FROM price_ranked
WHERE price_rank <= 15
ORDER BY product_id, price_rank
""".replace("\n", " ").replace("  ", " ")

    raw = psql_q(sql)

    cards_by_product: dict[str, list[dict]] = {}
    for line in raw.strip().splitlines():
        if not line.strip(): continue
        parts = line.split("|")
        if len(parts) < 9: continue
        pid, cid, name, rarity, col, ko_price, ko_source, p_rank, r_rank = parts[:9]
        cards_by_product.setdefault(pid, []).append({
            "card_id": cid,
            "name": name,
            "rarity": rarity,
            "col": col,
            "ko_price": int(ko_price) if ko_price else None,
            "ko_source": ko_source or "-",
            "p_rank": int(p_rank),
            "r_rank": int(r_rank),
        })

    lines = [
        "# 도감 힛카드 — 가격 포함 후보 v3 (사용자 명시)",
        "",
        "**우선순위**: 가격 desc → rarity priority → collection_number",
        "",
        "**컬럼**:",
        "- price_rank: 가격 순위 (시리즈 안에서)",
        "- rarity_rank: rarity priority 순위 (참고용)",
        "- 가격: KO 예상가 (price_snapshots source=KO_ESTIMATED 최신)",
        "- 가격 없으면 '-' (시세 부재 = 인기/유통 적음)",
        "",
        "각 시리즈마다 가격순 top 15 표시. 사용자가 보고 최종 4장 선정.",
        "",
        "---",
        "",
    ]

    for prod in products:
        pid = prod["productId"]
        pname = prod["productName"]
        ko_visible = prod["totalKoVisible"]
        cards = cards_by_product.get(pid, [])

        # 가격 있는 카드 수.
        priced_count = sum(1 for c in cards if c["ko_price"] is not None)
        max_price = max((c["ko_price"] for c in cards if c["ko_price"]), default=0)

        lines.append(f"## {pname}")
        lines.append("")
        lines.append(f"- product_id: `{pid}`")
        lines.append(f"- KO visible {ko_visible}장 · 가격 있는 카드 {priced_count}/{len(cards)} · 최고가 {max_price:,}원" if max_price else f"- KO visible {ko_visible}장 · 가격 없음")
        lines.append("")
        lines.append("| price_rank | rarity_rank | rarity | col# | 카드명 | 가격(원) | card_id |")
        lines.append("|---|---|---|---|---|---|---|")
        for c in cards:
            price_str = f"{c['ko_price']:,}" if c["ko_price"] else "-"
            lines.append(f"| {c['p_rank']} | {c['r_rank']} | {c['rarity']} | {c['col']} | {c['name']} | {price_str} | `{c['card_id']}` |")
        lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    total = sum(len(v) for v in cards_by_product.values())
    print(f"[ok] {OUT}")
    print(f"  products: {len(products)} / 후보 카드 총: {total}")
    print(f"  가격 있는 product: {sum(1 for v in cards_by_product.values() if any(c['ko_price'] for c in v))}/{len(cards_by_product)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
