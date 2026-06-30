"""
Phase A.3 — DB product 와 사이트 후보 fuzzy 매칭.

입력:
  raw_official.json   (scrape.py 결과)
  db_products.tsv     (prod DB 추출 — product_id | name | ko_visible | latest_card_at)

알고리즘:
  1. 텍스트 정규화 — 「」 제거, 다중 공백 → 단일 공백, 양끝 strip.
  2. SequenceMatcher.ratio() 점수.
  3. 각 DB product 마다 top-3 사이트 후보 선정 (score desc).

출력:
  match_candidates.json — review.html 의 입력.

score 임계값 (review.html 에서 사용):
  ≥ 0.90  자동 default 체크 (사용자 일괄 확정 빠름)
  0.70~0.89  사용자 검토 권장
  < 0.70  pass 권장 (옛날/특수 시리즈 매칭 안 될 가능성 큼)
"""

from __future__ import annotations
import json
import re
import sys
from difflib import SequenceMatcher
from pathlib import Path


HERE = Path(__file__).parent
RAW = HERE / "raw_official.json"
DB_TSV = HERE / "db_products.tsv"
OUT = HERE / "match_candidates.json"

NORMALIZE_PATTERN = re.compile(r"[「」『』【】\[\]\(\)（）]")
WHITESPACE_PATTERN = re.compile(r"\s+")


def normalize(s: str) -> str:
    """매칭용 정규화 — bracket 제거 + 공백 정규화. 의미있는 단어(확장팩/MEGA 등)는 유지."""
    if not s:
        return ""
    s = NORMALIZE_PATTERN.sub(" ", s)
    s = WHITESPACE_PATTERN.sub(" ", s).strip()
    return s


def score(a: str, b: str) -> float:
    """ratio 0.0~1.0. 정규화 후 SequenceMatcher."""
    na, nb = normalize(a), normalize(b)
    if not na or not nb:
        return 0.0
    return SequenceMatcher(None, na, nb).ratio()


def load_db() -> list[dict]:
    rows: list[dict] = []
    for line in DB_TSV.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        parts = line.split("|")
        if len(parts) < 4:
            continue
        rows.append({
            "product_id": parts[0],
            "db_name": parts[1],
            "ko_visible": int(parts[2] or 0),
            "latest_card_at": parts[3] if len(parts) > 3 else None,
        })
    return rows


def load_official(categories: set[str] | None = None) -> list[dict]:
    items = json.loads(RAW.read_text(encoding="utf-8"))
    if categories:
        items = [x for x in items if x.get("category") in categories]
    return items


def main() -> int:
    # 2026-05-29 사용자 명시 — 확장팩(info1) 만 후보로. info2/info3 제거 → 매칭 noise 감소.
    # DB 측은 ko_visible > 0 인 product 만 (이미 db_products.tsv 가 그렇게 필터됨).
    only_extension_packs = "--all" not in sys.argv
    db_rows = load_db()
    cats = {"info1"} if only_extension_packs else None
    official = load_official(cats)
    print(f"[match] DB {len(db_rows)} products vs site {len(official)} candidates "
          f"(filter: {'info1 only' if only_extension_packs else 'all categories'})",
          file=sys.stderr)

    results: list[dict] = []
    for db in db_rows:
        scored = []
        for c in official:
            s = score(db["db_name"], c["title"])
            scored.append((s, c))
        scored.sort(key=lambda x: x[0], reverse=True)
        top3 = [{
            "score": round(s, 4),
            "official_title": c["title"],
            "image_url": c["image_url"],
            "category": c["category"],
            "category_label": c["category_label"],
            "site_card_id": c["site_card_id"],
        } for s, c in scored[:3]]
        results.append({
            "product_id": db["product_id"],
            "db_name": db["db_name"],
            "ko_visible": db["ko_visible"],
            "latest_card_at": db["latest_card_at"],
            "candidates": top3,
        })

    # 통계 — score 분포 보고.
    by_top1 = {"≥0.90": 0, "0.70~0.89": 0, "<0.70": 0}
    for r in results:
        s = r["candidates"][0]["score"] if r["candidates"] else 0
        if s >= 0.90: by_top1["≥0.90"] += 1
        elif s >= 0.70: by_top1["0.70~0.89"] += 1
        else: by_top1["<0.70"] += 1

    OUT.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[ok] {len(results)} matches → {OUT}", file=sys.stderr)
    print(f"  top-1 score 분포: {by_top1}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
