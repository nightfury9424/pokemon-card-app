"""
Phase A.1 — pokemoncard.co.kr 공식 사이트 시리즈/박스 이미지 후보 스크랩.

3 페이지 (info1: 확장팩 / info2: 구축덱 / info3: 특별제품) 의 article.white-panel 추출:
  - title (h4 text + img alt)
  - image_url (data1.pokemonkorea.co.kr CDN)
  - site_card_id (onclick=/card/{id}, 사이트 내부 ID — 매핑 추적용)
  - category (info1/info2/info3)

출력: raw_official.json — 다음 단계 match.py 의 입력.

CLAUDE.md 의 "pokemonkorea.co.kr URL 사용 금지" 는 카드 이미지 hotlink 한정.
박스 이미지는 우리 저장소에 저장하기 위한 매핑 후보 수집이라 적용 안 됨.
"""

from __future__ import annotations
import json
import sys
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
BASE = "https://pokemoncard.co.kr"
CATEGORIES = {
    "info1": "확장팩",
    "info2": "구축덱",
    "info3": "특별제품",
}


class WhitePanelParser(HTMLParser):
    """site article.white-panel 추출. stdlib 만 사용 — BeautifulSoup 의존성 회피.

    구조 (확인됨):
      <article class="white-panel">
        <div class="point" onclick="location.href='/card/887'">
          <div class="white-panel-img">
            <img src="https://data1..." alt="MEGA 확장팩 「닌자스피너」">
          </div>
          <h4>MEGA 확장팩 「닌자스피너」</h4>
        </div>
        <a class="btn btn-buy" ...>구매하기</a>
      </article>
    """

    def __init__(self, category_key: str, category_label: str):
        super().__init__()
        self.category_key = category_key
        self.category_label = category_label
        self.results: list[dict] = []

        self._inside_article = False
        self._current: dict | None = None
        self._capture_h4 = False
        self._h4_buf = []

    def handle_starttag(self, tag, attrs):
        a = dict(attrs)

        if tag == "article" and "white-panel" in (a.get("class") or ""):
            self._inside_article = True
            self._current = {
                "category": self.category_key,
                "category_label": self.category_label,
                "site_card_id": None,
                "title": None,
                "image_url": None,
                "alt": None,
            }
            return

        if not self._inside_article or self._current is None:
            return

        if tag == "div" and "point" in (a.get("class") or ""):
            onclick = a.get("onclick") or ""
            # onclick="location.href='/card/887'"
            if "/card/" in onclick:
                try:
                    sid = onclick.split("/card/")[1].split("'")[0]
                    self._current["site_card_id"] = sid
                except Exception:
                    pass

        if tag == "img" and self._current.get("image_url") is None:
            src = a.get("src") or ""
            if "data1.pokemonkorea.co.kr" in src:
                self._current["image_url"] = src
                self._current["alt"] = a.get("alt")

        if tag == "h4":
            self._capture_h4 = True
            self._h4_buf = []

    def handle_endtag(self, tag):
        if not self._inside_article or self._current is None:
            return

        if tag == "h4" and self._capture_h4:
            self._capture_h4 = False
            text = "".join(self._h4_buf).strip()
            if text and not self._current.get("title"):
                self._current["title"] = text

        if tag == "article":
            if self._current.get("image_url") and self._current.get("title"):
                self.results.append(self._current)
            self._inside_article = False
            self._current = None
            self._capture_h4 = False

    def handle_data(self, data):
        if self._capture_h4:
            self._h4_buf.append(data)


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read().decode("utf-8", errors="replace")


def main() -> int:
    all_items: list[dict] = []
    for key, label in CATEGORIES.items():
        url = f"{BASE}/card/category/{key}"
        print(f"[scrape] {url} ({label})", file=sys.stderr)
        try:
            html = fetch(url)
        except Exception as e:
            print(f"  ! fetch 실패: {e}", file=sys.stderr)
            continue

        parser = WhitePanelParser(key, label)
        parser.feed(html)
        print(f"  → {len(parser.results)} 시리즈", file=sys.stderr)
        all_items.extend(parser.results)

    out = Path(__file__).parent / "raw_official.json"
    out.write_text(
        json.dumps(all_items, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"[ok] {len(all_items)} 시리즈 → {out}", file=sys.stderr)

    # 카테고리별 카운트.
    by_cat: dict[str, int] = {}
    for it in all_items:
        by_cat[it["category"]] = by_cat.get(it["category"], 0) + 1
    for k, v in by_cat.items():
        print(f"    {k} ({CATEGORIES[k]}): {v}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main())
