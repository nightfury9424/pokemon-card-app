"""SNKRDUNK Stage-1 PoC PROBE — apparel 상세 JSON 엔드포인트 확인용 (kream_ditto.py 패턴 복제).
★실행 안 됨/미완성 SKELETON. ENDPOINT 미확정 → 먼저 DevTools Network 로 잡아야 함(아래 STEP 0).
★prod write 0 · 가격반영 0 · evidence CSV 만. 자동 anchor 금지. 정중한 크롤(딜레이/체크포인트).

전제(KREAM과 동일): 별도 Chrome 인스턴스가
  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome \\
    --remote-debugging-port=9222 --user-data-dir=/tmp/chrome_snkrdunk_profile
로 떠 있고, snkrdunk.com 페이지 1개가 열려(로그인) 있어야 함. (메타몽 방식 그대로)

STEP 0 (가장 초기 1단계 — 사람이 직접):
  1) 위 Chrome 로 snkrdunk.com/apparels/753273 열기
  2) DevTools(F12) → Network → Fetch/XHR 필터
  3) 페이지 새로고침 → 最近の売買履歴 / 売買相場 / 상품정보 를 싣는 XHR 의
     (a) URL  (b) method  (c) 응답 JSON 모양  (d) 인증헤더 패턴  기록
  4) 그 URL 을 아래 SALES_ENDPOINT / DETAIL_ENDPOINT 에 채움
  → 그 전까지 이 스크립트는 동작 안 함(의도된 상태).
"""
import asyncio, logging, sys
from datetime import datetime

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("snkrdunk_probe")

CDP_URL = "http://localhost:9222"
SNKRDUNK_HOST = "snkrdunk.com"

# ★TODO: DevTools Network 로 확인 후 채울 것 (현재 전부 미확정 = 동작 안 함)
DETAIL_ENDPOINT = None   # 예: "https://snkrdunk.com/v1/apparels/{apparel_id}"  ← 확인 필요
SALES_ENDPOINT  = None   # 예: "https://snkrdunk.com/v1/apparels/{apparel_id}/sales?..."  ← 확인 필요
ALLOWED_GRADES = {"A", "PSA10", "PSA9"}   # ★이 3개만. 그 외(B/C/D·PSA8↓·BGS/CGC) drop.


async def probe_apparel(apparel_id: str) -> dict | None:
    """CDP attach → snkrdunk 페이지 컨텍스트에서 자기 axios/fetch 로 JSON 호출 (KREAM 패턴).
    엔드포인트 미확정이면 즉시 중단(절대 추측 호출 안 함)."""
    if not (DETAIL_ENDPOINT and SALES_ENDPOINT):
        log.error("ENDPOINT 미확정. STEP 0(DevTools Network)부터. 추측 호출 금지 → 종료.")
        sys.exit(4)
    try:
        from playwright.async_api import async_playwright
    except ImportError:
        log.error("playwright 미설치 (KREAM venv 참고: python/.venv_kream).")
        sys.exit(5)
    async with async_playwright() as pw:
        try:
            browser = await pw.chromium.connect_over_cdp(CDP_URL, timeout=5000)
        except Exception as exc:
            log.error("CDP attach 실패(%s). Chrome 9222 떠있어야 함.", exc)
            sys.exit(2)
        target = next((p for ctx in browser.contexts for p in ctx.pages if SNKRDUNK_HOST in (p.url or "")), None)
        if target is None:
            log.error("snkrdunk.com 페이지 없음. 인스턴스에 1개 열어둘 것.")
            sys.exit(3)
        log.info("[CDP] attached. page=%s", target.url)
        # 페이지 컨텍스트에서 fetch (쿠키/토큰 자동) — 응답 모양 확인용
        sales = await target.evaluate(
            """async (url) => { const r = await fetch(url, {credentials:'include'});
                                return { status: r.status, body: await r.text() }; }""",
            SALES_ENDPOINT.format(apparel_id=apparel_id))
        log.info("[probe] http=%s len=%s", sales.get("status"), len(sales.get("body", "")))
        return sales  # ← Stage-1 에선 그냥 raw 출력만. 파싱/매핑/저장은 다음 단계.


def normalize_grade(raw: str) -> str | None:
    """状態 텍스트 → {A,PSA9,PSA10} 또는 None(제외). 中古/新品 prefix·공백 제거."""
    s = (raw or "").upper().replace("中古", "").replace("新品", "").strip()
    if s in ALLOWED_GRADES:
        return s
    return None  # B/C/D·PSA8↓·BGS/CGC → drop


def parse_jp_date(raw: str, scraped_at: datetime) -> datetime | None:
    """'2026/06/13' 절대 / 'N時間前·N日前·N週間前' 상대(scraped_at 기준, JST) → datetime. 미해석 None."""
    raise NotImplementedError("Stage-1 파서 미구현 — STEP 0 응답 모양 확인 후 작성")


if __name__ == "__main__":
    # PoC: 단일 apparel_id 한 개만 (753273 = メガピクシーex SAR, 구조 샘플 — 우리 카드 가정 금지)
    asyncio.run(probe_apparel(sys.argv[1] if len(sys.argv) > 1 else "753273"))
