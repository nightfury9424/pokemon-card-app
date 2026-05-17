"""pokemoncard.co.kr에서 SM-P 프로모 카드 메타 보강.

DB의 cards 테이블에서 official_card_code LIKE 'SMP%' 카드를 모두 가져와서
각 페이지를 크롤링한 뒤 collection_number / illustrator 등을 추출.
결과는 data/promo_staging.json에 저장 (DB 즉시 update 안 함).

사용자가 review_promo.html에서 검수 후 일괄 apply.
"""

from __future__ import annotations
import json
import os
import sys
import time
from pathlib import Path

import psycopg2
import requests
from bs4 import BeautifulSoup
from tqdm import tqdm

OUT = Path(__file__).parent / "data" / "promo_staging.json"
URL_TMPL = "https://pokemoncard.co.kr/cards/detail/{code}"
UA = "Mozilla/5.0 (PokeFolioMetaSync/0.1)"
TIMEOUT = 15
SLEEP = 0.5  # polite delay


def db_connect():
    return psycopg2.connect(
        host="localhost",
        user="nightfury",
        dbname="pokemon_card_db",
        password=os.environ.get("DB_PASSWORD", ""),
    )


def fetch_cards_to_enrich(conn) -> list[dict]:
    """SMP 코드 카드 전부 가져옴. 검수 UI가 KO/JP/EN 이미지 비교용 ref도 같이 필요."""
    sql = """
        SELECT card_id, official_card_code, name,
               COALESCE(collection_number, '') AS collection_number,
               COALESCE(illustrator, '') AS illustrator,
               COALESCE(image_url, '') AS image_url,
               COALESCE(jp_scrydex_ref, '') AS jp_scrydex_ref,
               COALESCE(en_scrydex_ref, '') AS en_scrydex_ref
          FROM cards
         WHERE official_card_code LIKE 'SMP%'
         ORDER BY official_card_code
    """
    with conn.cursor() as cur:
        cur.execute(sql)
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def parse_page(html: str) -> dict:
    """페이지에서 collection_number, illustrator 추출."""
    soup = BeautifulSoup(html, "lxml")
    out: dict = {}
    # 카드 번호: <span class="p_num">117/SM-P  </span>
    num = soup.select_one(".p_num")
    if num:
        # 안에 빈 wrap span 등 있을 수 있어서 텍스트 정리
        text = num.get_text(strip=True)
        # 끝에 붙은 공백/특수문자 제거
        out["collection_number"] = text.strip()
    # 일러스트: <p class="illustrator">일러스트<br />5ban Graphics</p>
    ill = soup.select_one(".illustrator")
    if ill:
        # "일러스트" 라벨 + <br/> 후 이름
        text = ill.get_text(separator="|", strip=True)
        parts = [p.strip() for p in text.split("|") if p.strip()]
        if len(parts) >= 2:
            out["illustrator"] = parts[1]
        elif len(parts) == 1 and parts[0] != "일러스트":
            out["illustrator"] = parts[0]
    return out


def fetch_one(code: str) -> dict | None:
    url = URL_TMPL.format(code=code)
    try:
        r = requests.get(url, headers={"User-Agent": UA}, timeout=TIMEOUT)
    except requests.RequestException as e:
        print(f"  fetch err {code}: {e}", file=sys.stderr)
        return None
    if r.status_code == 404:
        return {"_404": True}
    if r.status_code != 200:
        print(f"  HTTP {r.status_code} for {code}", file=sys.stderr)
        return None
    return parse_page(r.text)


def main() -> int:
    conn = db_connect()
    cards = fetch_cards_to_enrich(conn)
    print(f"SM-P 카드 {len(cards)}장 — pokemoncard.co.kr 크롤링 시작")

    results = []
    for card in tqdm(cards):
        code = card["official_card_code"]
        scraped = fetch_one(code)
        time.sleep(SLEEP)
        if scraped is None or scraped.get("_404"):
            results.append({
                **card,
                "scraped": {},
                "status": "not_found" if scraped and scraped.get("_404") else "error",
                "url": URL_TMPL.format(code=code),
            })
            continue
        results.append({
            **card,
            "scraped": scraped,
            "status": "ok",
            "url": URL_TMPL.format(code=code),
        })

    # diff 미리 계산해서 viewer에서 빠르게 표시
    for r in results:
        s = r.get("scraped") or {}
        diff = {}
        for key in ("collection_number", "illustrator"):
            cur = (r.get(key) or "").strip()
            new = (s.get(key) or "").strip()
            if new and new != cur:
                diff[key] = {"current": cur, "new": new}
        r["diff"] = diff

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(results, ensure_ascii=False, indent=2))

    ok = sum(1 for r in results if r["status"] == "ok")
    not_found = sum(1 for r in results if r["status"] == "not_found")
    has_diff = sum(1 for r in results if r.get("diff"))
    print(f"\n완료 — ok {ok}, not_found {not_found}, diff {has_diff}장")
    print(f"저장: {OUT}")
    print("\n다음: review_promo_server.py 실행하고 브라우저에서 검수")
    conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
