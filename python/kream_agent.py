#!/usr/bin/env python3
"""메타몽 KREAM 수집 맥북 agent.

admin 페이지 버튼이 prod 에 'REQUESTED' flag 를 세우면, 이 agent(맥북=가정 IP)가
KREAM 제품 페이지를 크롤(curl_cffi, 로그인/JWT 불필요)해서 (등급/가격/날짜) 추출 →
prod ingest 로 push. KREAM 봇탐지가 prod 서버 IP 는 막지만 맥북 IP 는 통과하므로 맥북에서 돈다.

실행 (맥북, 아무 네트워크나 OK):
  KREAM_AGENT_TOKEN=<prod 와 동일> python3 kream_agent.py
  # POKEFOLIO_API 기본 https://52.78.3.120.nip.io / KREAM_POLL_SEC 기본 10
백그라운드 상시:  nohup ... &   또는 launchd.
"""
import datetime
import os
import re
import sys
import time

from curl_cffi import requests as cffi

API = os.environ.get("POKEFOLIO_API", "https://52.78.3.120.nip.io").rstrip("/")
TOKEN = os.environ.get("KREAM_AGENT_TOKEN", "")
POLL = int(os.environ.get("KREAM_POLL_SEC", "10"))
PRODUCT_URL = os.environ.get("KREAM_PRODUCT_URL", "https://kream.co.kr/products/508949")

# 등급 + 가격 + (빠른배송) + 날짜(상대/절대) 추출.
ROW = re.compile(
    r"(Ungraded|PSA \d+ \(Card Ver\.\)|BRG \d+\s*(?:영문|한글)?)\s*"
    r"([\d,]+)\s*원\s*(?:빠른배송\s*)?"
    r"(\d+\s*시간 전|\d+\s*분 전|방금|\d+\s*일 전|\d{2}/\d{2}/\d{2})"
)


def map_grade(g):
    """표시 등급 → (cardStatus, gradingCompany, gradeValue, title)."""
    if g.startswith("Ungraded"):
        return ("RAW", None, None, "Ungraded")
    m = re.match(r"(PSA|BRG)\s*(\d+)", g)
    if m:
        return ("GRADED", m.group(1), m.group(2), g.strip())
    return None


def parse_date(s, now):
    s = s.strip()
    if "방금" in s:
        return now
    m = re.search(r"(\d+)\s*분", s)
    if m and "분" in s:
        return now - datetime.timedelta(minutes=int(m.group(1)))
    m = re.search(r"(\d+)\s*시간", s)
    if m:
        return now - datetime.timedelta(hours=int(m.group(1)))
    m = re.search(r"(\d+)\s*일", s)
    if m:
        return now - datetime.timedelta(days=int(m.group(1)))
    m = re.match(r"(\d{2})/(\d{2})/(\d{2})", s)
    if m:
        return datetime.datetime(2000 + int(m.group(1)), int(m.group(2)),
                                 int(m.group(3)), 12, 0)
    return None


def crawl():
    r = cffi.get(PRODUCT_URL, impersonate="chrome124", timeout=20,
                 headers={"Accept": "text/html", "Accept-Language": "ko-KR,ko;q=0.9"})
    if r.status_code != 200:
        raise RuntimeError(f"KREAM 페이지 {r.status_code} (이 네트워크 IP 가 막혔을 수 있음)")
    txt = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", r.text))
    rows = ROW.findall(txt)
    # 페이지가 pc/mobile 레이아웃으로 같은 리스트를 2번 렌더 → 정확히 반복이면 절반만.
    n = len(rows)
    if n >= 2 and n % 2 == 0 and rows[: n // 2] == rows[n // 2:]:
        rows = rows[: n // 2]
    now = datetime.datetime.now()
    sales = []
    for g, p, d in rows:
        mg = map_grade(g)
        dt = parse_date(d, now)
        if not mg or not dt:
            continue
        cs, comp, val, title = mg
        sales.append({
            "cardStatus": cs, "gradingCompany": comp, "gradeValue": val,
            "title": title, "price": int(p.replace(",", "")),
            "tradedAt": dt.replace(microsecond=0).isoformat(),
        })
    return sales


def post_ingest(sales=None, error=None):
    body = {"sales": sales or [], "error": error}
    r = cffi.post(f"{API}/api/kream-agent/ingest", json=body,
                  headers={"X-Kream-Agent-Token": TOKEN}, timeout=30,
                  impersonate="chrome124")
    return r.status_code, r.text[:200]


def loop():
    print(f"[agent] start API={API} poll={POLL}s", flush=True)
    while True:
        try:
            r = cffi.get(f"{API}/api/kream-agent/claim",
                         headers={"X-Kream-Agent-Token": TOKEN}, timeout=15,
                         impersonate="chrome124")
            if r.status_code == 200 and r.json().get("claim"):
                print("[agent] 요청 감지 → KREAM 크롤 시작", flush=True)
                try:
                    sales = crawl()
                    sc, txt = post_ingest(sales=sales)
                    ung = sum(1 for s in sales if s["title"] == "Ungraded")
                    print(f"[agent] {len(sales)}건(Ungraded {ung}) ingest → {sc} {txt}", flush=True)
                except Exception as e:
                    print(f"[agent] 크롤 실패: {e}", flush=True)
                    post_ingest(error=str(e))
            elif r.status_code != 200:
                print(f"[agent] claim {r.status_code} (토큰/연결 확인)", flush=True)
        except Exception as e:
            print(f"[agent] poll error: {e}", flush=True)
        time.sleep(POLL)


if __name__ == "__main__":
    if not TOKEN:
        print("환경변수 KREAM_AGENT_TOKEN 필요 (prod .env.prod 와 동일 값)")
        sys.exit(1)
    loop()
