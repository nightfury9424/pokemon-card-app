"""
review.html + match_candidates.json → review_offline.html (standalone).

브라우저가 file:// 에서 fetch() 차단하므로 JSON 을 HTML 안에 inline embed.
사용자가 그냥 `open review_offline.html` 하면 즉시 동작 (서버 X).
"""

from __future__ import annotations
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
TEMPLATE = HERE / "review.html"
DATA = HERE / "match_candidates.json"
OUT = HERE / "review_offline.html"

FETCH_PATTERN = """function fetchData() {
  return fetch('match_candidates.json')
    .then(r => r.json())
    .then(d => { DATA = d; })
    .catch(() => {
      document.body.innerHTML = '<div style="padding:40px;color:#f87171">match_candidates.json 못 읽음. python3 match.py 먼저 실행.</div>';
    });
}"""


def main() -> int:
    template = TEMPLATE.read_text(encoding="utf-8")
    data = json.loads(DATA.read_text(encoding="utf-8"))
    # </script> 같은 escape 안전 — JSON 안의 / 는 그대로 OK, 다만 </script> 시퀀스만 회피.
    data_json = json.dumps(data, ensure_ascii=False).replace("</", "<\\/")

    replacement = f"""function fetchData() {{
  // 2026-05-29 build_offline.py 가 match_candidates.json 을 inline embed.
  DATA = {data_json};
  return Promise.resolve();
}}"""

    if FETCH_PATTERN not in template:
        print("[err] FETCH_PATTERN 못 찾음 — review.html 이 수정되어 인라인 빌드 실패.",
              file=sys.stderr)
        return 1

    new_html = template.replace(FETCH_PATTERN, replacement)
    OUT.write_text(new_html, encoding="utf-8")
    print(f"[ok] {OUT} ({len(new_html):,} bytes — JSON {len(data)} matches embedded)",
          file=sys.stderr)
    print(f"     사용법: open {OUT}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
