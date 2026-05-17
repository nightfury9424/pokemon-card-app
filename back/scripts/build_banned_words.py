#!/usr/bin/env python3
"""
hlog2e + doublems의 한국어 욕설 리스트를 받아 중복/짧은 단어 제거 후
back/src/main/resources/banned/banned_words.txt로 저장한다.

빌드 의존이 아니라 사람이 1회 실행 (또는 리스트 업데이트 시) 하는 도구.
서버 부팅 시 외부 URL을 호출하지 않기 위함.

Usage:
  python3 back/scripts/build_banned_words.py
"""
import json
import re
import sys
import urllib.request
from pathlib import Path

HLOG2E_URL = "https://cdn.jsdelivr.net/gh/hlog2e/bad_word_list@master/word_list.json"
DOUBLEMS_URL = "https://raw.githubusercontent.com/doublems/korean-bad-words/master/korean-bad-words.md"

OUT_PATH = Path(__file__).resolve().parents[1] / "src/main/resources/banned/banned_words.txt"
WHITELIST_PATH = Path(__file__).resolve().parents[1] / "src/main/resources/banned/banned_whitelist.txt"
MIN_LEN = 2  # 1글자 단어는 일반명사 오탐 위험 ↑


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "build-banned-words"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8")


def parse_hlog2e(body: str) -> list[str]:
    data = json.loads(body)
    if isinstance(data, dict) and "words" in data:
        return [str(x) for x in data["words"]]
    if isinstance(data, list):
        return [str(x) for x in data]
    return []


def parse_doublems(body: str) -> list[str]:
    """markdown — 코드 블럭/리스트 둘 다 케이스 발생. 한글/영문/숫자 토큰만 뽑음."""
    tokens: list[str] = []
    for line in body.splitlines():
        line = line.strip()
        if not line or line.startswith("#") or line.startswith("|"):
            continue
        cleaned = re.sub(r"^[\-\*\+\d\.\s`>]+", "", line).strip("` ").strip()
        if cleaned:
            tokens.append(cleaned)
    return tokens


def normalize_word(w: str) -> str:
    return w.strip().lower()


def main() -> int:
    words: set[str] = set()
    for label, url, parser in [
        ("hlog2e", HLOG2E_URL, parse_hlog2e),
        ("doublems", DOUBLEMS_URL, parse_doublems),
    ]:
        try:
            body = fetch(url)
            collected = parser(body)
            print(f"[{label}] {len(collected)} raw")
            for w in collected:
                w = normalize_word(w)
                if len(w) >= MIN_LEN:
                    words.add(w)
        except Exception as e:
            print(f"[{label}] FAILED: {e}", file=sys.stderr)

    if not words:
        print("aborted: empty banned list", file=sys.stderr)
        return 1

    # 화이트리스트 적용 — 일반명사화/오탐 단어를 final 리스트에서 제외
    whitelist: set[str] = set()
    if WHITELIST_PATH.exists():
        for line in WHITELIST_PATH.read_text(encoding="utf-8").splitlines():
            t = line.strip()
            if t and not t.startswith("#"):
                whitelist.add(t.lower())
    removed = words & whitelist
    words -= whitelist
    print(f"[whitelist] excluded {len(removed)} words: {sorted(removed)}")

    sorted_words = sorted(words)
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    header = "# 자동 생성됨 — back/scripts/build_banned_words.py\n"
    header += "# 출처: hlog2e/bad_word_list, doublems/korean-bad-words\n"
    header += "# 화이트리스트(banned_whitelist.txt)에 명시된 단어는 자동 제외됨.\n"
    OUT_PATH.write_text(header + "\n".join(sorted_words) + "\n", encoding="utf-8")
    print(f"wrote {len(sorted_words)} words → {OUT_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
