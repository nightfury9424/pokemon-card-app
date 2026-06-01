"""
2026-05-30 Phase B — 도감 힛카드 후보 markdown 생성.

입력:
  /tmp/dex40.json — /api/assets/dex?limit=40 응답 (40 products)
  prod DB cards table — rarity priority + collection_number 정렬

출력:
  python/box_image_mapping/hits_candidates.md — 사용자가 직접 정리할 markdown

후보 기준 (사용자 명시):
  - rarity priority (MUR > BWR > SAR > SSR > UR > HR > CSR > SR > AR > ACE > RRR > RR > H > R > U > C > S > K > PR)
  - collection_number 보조
  - 각 product 별 top 10 카드
  - card_id, card_name, rarity_code, collection_number, 자동 rank 표시

사용자가 markdown 보고 ★ 4장씩 표시 → 다음 cycle 에서 backend override 적용.
"""
from __future__ import annotations
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).parent
DEX_JSON = Path("/tmp/dex40.json")
OUT = HERE / "hits_candidates.md"

SSH_KEY = "/Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem"
PROD_USER = "ubuntu@52.78.3.120"

# RARITY priority — backend DexService 와 동일.
RARITY_CASE = """
CASE c.rarity_code
  WHEN 'MUR' THEN 1 WHEN 'BWR' THEN 2 WHEN 'SAR' THEN 3 WHEN 'SSR' THEN 4
  WHEN 'UR'  THEN 5 WHEN 'HR'  THEN 6 WHEN 'CSR' THEN 7 WHEN 'SR'  THEN 8
  WHEN 'AR'  THEN 9 WHEN 'ACE' THEN 10 WHEN 'RRR' THEN 11 WHEN 'RR' THEN 12
  WHEN 'H'   THEN 13 WHEN 'R'  THEN 14 WHEN 'U'   THEN 15 WHEN 'C'  THEN 16
  WHEN 'S'   THEN 17 WHEN 'K'  THEN 18 WHEN 'PR'  THEN 99 ELSE 50
END
"""

def psql_query(sql: str) -> str:
    """prod docker psql 직접 실행 → TSV (pipe-separated)."""
    cmd = [
        "ssh", "-i", SSH_KEY, PROD_USER,
        f"docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -t -A -F'|' -c \"{sql}\""
    ]
    return subprocess.check_output(cmd, text=True)


def main() -> int:
    dex = json.loads(DEX_JSON.read_text())
    products = dex["data"]["products"]
    product_ids = [p["productId"] for p in products]

    # IN 절용 string.
    ids_in = ",".join(f"'{pid}'" for pid in product_ids)

    sql = f"""
SELECT c.product_id, c.card_id, c.name, c.rarity_code,
       COALESCE(c.collection_number, ''),
       {RARITY_CASE.strip()} AS pri,
       ROW_NUMBER() OVER (
         PARTITION BY c.product_id
         ORDER BY {RARITY_CASE.strip()}, c.collection_number ASC NULLS LAST, c.card_id
       ) AS rank
FROM cards c
WHERE c.is_visible = TRUE AND c.language = 'KO'
  AND c.product_id IN ({ids_in})
ORDER BY c.product_id, rank
""".replace("\n", " ").replace("  ", " ")

    raw = psql_query(sql)

    # parse
    cards_by_product: dict[str, list[dict]] = {}
    for line in raw.strip().splitlines():
        if not line.strip(): continue
        parts = line.split("|")
        if len(parts) < 7: continue
        pid, cid, name, rarity, col_num, pri, rank = parts[:7]
        cards_by_product.setdefault(pid, []).append({
            "card_id": cid,
            "name": name,
            "rarity": rarity,
            "col_num": col_num,
            "pri": int(pri),
            "rank": int(rank),
        })

    # markdown
    lines = [
        "# 도감 힛카드 후보 (사용자 정리용)",
        "",
        f"각 시리즈마다 후보 top 10 카드 (rarity priority + collection_number 정렬).",
        f"이 중 **각 시리즈 4장**을 ★ 표시해서 정리 부탁드립니다.",
        "",
        "정리 방법 예시:",
        "```",
        "1. **★** | MUR | 001 | 메가지가르데 EX  | CRD_xxx",
        "2.   | SAR | 002 | 리자몽 ex        | CRD_xxx",
        "```",
        "→ 1번 카드를 힛카드로 선택 (앞에 ★).",
        "",
        "rarity priority: MUR > BWR > SAR > SSR > UR > HR > CSR > SR > AR > ACE > RRR > RR > H > R > U > C > S > K > PR",
        "",
        "---",
        "",
    ]

    for prod in products:
        pid = prod["productId"]
        pname = prod["productName"]
        ko_visible = prod["totalKoVisible"]
        cards = cards_by_product.get(pid, [])[:10]   # top 10

        lines.append(f"## {pname}")
        lines.append("")
        lines.append(f"- product_id: `{pid}`")
        lines.append(f"- KO visible 카드: {ko_visible}장")
        lines.append("")
        lines.append("| rank | rarity | col# | 카드명 | card_id |")
        lines.append("|------|--------|------|--------|---------|")
        for c in cards:
            mark = ""   # 사용자가 ★ 채워줌
            lines.append(f"| {c['rank']}.{mark} | {c['rarity']} | {c['col_num']} | {c['name']} | `{c['card_id']}` |")
        lines.append("")

    OUT.write_text("\n".join(lines), encoding="utf-8")
    print(f"[ok] {OUT}")
    print(f"  products: {len(products)}")
    print(f"  총 후보 카드: {sum(len(v[:10]) for v in cards_by_product.values())}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
