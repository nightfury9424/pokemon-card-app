"""당근 매물 list 크롤링 v2 — Playwright + sold + 90일 cutoff + seed JSON load.

CLI:
  --source {priority,seoul,all}      seed 데이터 source (default: priority)
  --phase {1차,2차,3차,all}          priority일 때 phase (default: 1차)
  --no-resume                        progress 파일 무시하고 처음부터

흐름:
- 두 JSON 에서 (dong_name, pid) seed list 생성 (pid dedupe)
- BFS 확장 OFF (이미 모든 region pid 보유)
- 각 region 크롤 → price_review_queue insert → progress 파일 update
- 중단 후 재실행 시 progress 파일의 완료 pid skip

저장:
- price_review_queue, source='DAANGN', source_id=detail URL hash
- 판매완료/거래완료 매물만 (sold filter), 박스/팩/일판/굿즈 제외 (SKIP_PATTERNS)
- image_path = 외부 webp URL 그대로
"""
from __future__ import annotations
import argparse
import json
import re
import time
from datetime import datetime, timedelta
from pathlib import Path
from playwright.sync_api import sync_playwright
import psycopg2

# Seed JSON paths (사용자 명시).
SEED_SEOUL_JSON = "/Users/fury/Downloads/서울특별시.json"
SEED_PRIORITY_JSON = "/Users/fury/Downloads/daangn_priority_regions_all.json"

# Progress 파일 — 완료된 region pid set 저장. 재실행 시 skip.
PROGRESS_FILE = Path("/tmp/crawl_daangn_progress.json")

SEARCH = "포켓몬카드"
DB = {"dbname": "pokemon_card_db", "user": "nightfury"}
CUTOFF_DAYS = 90  # 사용자 정책 — 최근 3개월
MAX_SCROLLS = 200
LOG = "/tmp/crawl_daangn_v2.log"

# 이미 JSON에 모든 region pid 모았으므로 BFS 자동 확장 OFF.
DISABLE_BFS = True


def load_seeds(source: str, phase: str) -> list[tuple[str, int]]:
    """JSON 에서 (dong_name, pid) seed list 생성. source 별 분기 + pid dedupe."""
    seeds: list[tuple[str, int]] = []
    if source in ("priority", "all"):
        with open(SEED_PRIORITY_JSON) as f:
            data = json.load(f)
        for ph, targets in data["priority_groups"].items():
            if phase != "all" and ph != phase:
                continue
            for _target, dongs in targets.items():
                for d in dongs:
                    seeds.append((d["dong_name"], d["pid"]))
    if source in ("seoul", "all"):
        with open(SEED_SEOUL_JSON) as f:
            data = json.load(f)
        for _sigungu, dongs in data["sigungu"].items():
            for d in dongs:
                seeds.append((d["dong_name"], d["pid"]))
    # pid dedupe — 첫 (dong_name) 우선
    seen_pids: set[int] = set()
    deduped: list[tuple[str, int]] = []
    for name, pid in seeds:
        if pid in seen_pids:
            continue
        seen_pids.add(pid)
        deduped.append((name, pid))
    return deduped


def load_progress() -> set[int]:
    if not PROGRESS_FILE.exists():
        return set()
    try:
        return set(json.loads(PROGRESS_FILE.read_text()))
    except Exception:
        return set()


def save_progress(completed_pids: set[int]) -> None:
    PROGRESS_FILE.write_text(json.dumps(sorted(completed_pids)))


def parse_days_ago(t: str | None) -> int | None:
    if not t:
        return None
    t = t.strip()
    if "오늘" in t or "시간 전" in t or "분 전" in t:
        return 0
    if "어제" in t:
        return 1
    m = re.match(r"(\d+)\s*일\s*전", t)
    if m:
        return int(m.group(1))
    m = re.match(r"(\d+)\s*주\s*전", t)
    if m:
        return int(m.group(1)) * 7
    m = re.match(r"(\d+)\s*(달|개월)\s*전", t)
    if m:
        return int(m.group(1)) * 30
    return None


def hash_from_href(href: str) -> str | None:
    m = re.search(r"-([a-z0-9]{8,16})/?$", href)
    return m.group(1) if m else None


def crawl_region(page, region_name: str, region_id: int) -> list[dict]:
    from urllib.parse import quote
    url = (f"https://www.daangn.com/kr/buy-sell/s/"
           f"?in={quote(region_name)}-{region_id}&search={quote(SEARCH)}")
    print(f"  [region {region_name}-{region_id}] {url}", flush=True)
    page.goto(url, wait_until="domcontentloaded", timeout=30000)
    page.wait_for_timeout(3000)

    prev_count = -1
    stable_count = 0
    for s in range(MAX_SCROLLS):
        # 스크롤 끝까지
        page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
        page.wait_for_timeout(900)

        # 매물 list 영역 더보기 button만 (footer "주변 지역 더보기" 제외)
        # → 매물 element 마지막의 ancestor 안 button[text="더보기"]
        clicked = False
        try:
            more_btn_handle = page.evaluate_handle("""
                () => {
                    const items = document.querySelectorAll('a[data-gtm="search_article"]');
                    if (!items.length) return null;
                    const last = items[items.length - 1];
                    let cur = last;
                    // 위로 5단계 ancestor 안에서 button[text="더보기"] 찾기.
                    // 2026-05-19 fix: footer/nav/aside + 부모 "주변 지역" 영역 제외.
                    // 잘못된 "주변 지역 더보기" 클릭 시 다른 region으로 navigate → 페이지 closed → crawl 실패.
                    const isValidMore = (b) => {
                        if (b.textContent.trim() !== '더보기') return false;
                        if (!b.offsetParent) return false;
                        if (b.closest('footer, nav, aside')) return false;
                        let p = b.parentElement;
                        for (let i = 0; i < 5 && p; i++, p = p.parentElement) {
                            const t = p.textContent || '';
                            if (t.includes('주변 지역') || t.includes('주변지역')) return false;
                        }
                        return true;
                    };
                    for (let d = 0; d < 8; d++) {
                        cur = cur.parentElement;
                        if (!cur) break;
                        const btns = Array.from(cur.querySelectorAll('button')).filter(isValidMore);
                        if (btns.length) return btns[btns.length - 1];
                    }
                    return null;
                }
            """)
            if more_btn_handle and more_btn_handle.as_element():
                el = more_btn_handle.as_element()
                el.scroll_into_view_if_needed(timeout=1000)
                page.wait_for_timeout(300)
                el.click(timeout=3000)
                page.wait_for_timeout(2500)
                clicked = True
        except Exception as e:
            pass

        items = page.evaluate(EXTRACT_JS)
        count = len(items)

        # 60일 cutoff 도달 시 break (모든 매물 시간 확인 후)
        all_old = items and all(
            (parse_days_ago(it.get("time")) or 0) > CUTOFF_DAYS
            for it in items[-10:]
        )
        if all_old and not clicked:
            print(f"    cutoff reached: last 10 items all > {CUTOFF_DAYS}d", flush=True)
            break

        if not clicked and count == prev_count:
            stable_count += 1
            print(f"    scroll {s}: count={count} (stable {stable_count})", flush=True)
            if stable_count >= 5:
                break
        else:
            stable_count = 0
            print(f"    scroll {s}: count={count} clicked={clicked}", flush=True)
        prev_count = count

    # 모든 매물 viewport 통과 → img lazy load 트리거
    print(f"    found {prev_count} items, scrolling each into view for img load", flush=True)
    page.evaluate("""
        async () => {
            const items = document.querySelectorAll('a[data-gtm="search_article"]');
            for (const el of items) {
                el.scrollIntoView({block: 'center', behavior: 'instant'});
                await new Promise(r => setTimeout(r, 60));
            }
        }
    """)
    page.wait_for_timeout(2000)  # 마지막 batch image load 대기

    items = page.evaluate(EXTRACT_JS)
    img_count = sum(1 for it in items if it.get("img"))
    print(f"    extracted: {len(items)} items, {img_count} with img", flush=True)
    return items


EXTRACT_JS = """
() => Array.from(document.querySelectorAll('a[data-gtm="search_article"]'))
    .map(a => {
        const img = a.querySelector('img');
        let imgSrc = null;
        if (img) {
            imgSrc = img.src || img.getAttribute('data-src') || img.dataset?.src || null;
            if (!imgSrc && img.srcset) {
                imgSrc = img.srcset.split(',')[0].trim().split(' ')[0];
            }
            if (imgSrc && (imgSrc.startsWith('data:') || imgSrc.length < 30)) imgSrc = null;
        }
        const spans = Array.from(a.querySelectorAll('span'));
        // 당근 DOM 에 따라 "판매완료" 또는 "거래완료" 두 가지 텍스트 출현 — 둘 다 sold 처리.
        const soldTexts = new Set(['판매완료', '거래완료']);
        const sold = !!spans.find(s => soldTexts.has(s.textContent.trim()));
        // 가격 — 텍스트가 "N,NNN원" 단독 패턴 span
        const priceSpan = spans.find(s => /^[0-9,]+원$/.test(s.textContent.trim()));
        const price = priceSpan
            ? parseInt(priceSpan.textContent.replace(/[원,]/g, '').trim())
            : null;
        // 시간 — <time> element (가장 안정)
        const timeEl = a.querySelector('time');
        let time = timeEl ? timeEl.textContent.trim() : null;
        if (time) time = time.replace(/^끌올\\s*/, '');  // "끌올 18시간 전" → "18시간 전"
        // 제목 — leaf span 중 가격/지역/시간/sold 제외 첫 번째 긴 span
        let title = null;
        for (const s of spans) {
            const t = s.textContent.trim();
            if (!t || t.length < 4) continue;
            if (t === '판매완료') continue;
            if (/^[0-9,]+원$/.test(t)) continue;
            if (t === '·') continue;
            // 시간 텍스트 제외
            if (/^(끌올\\s*)?\\d+\\s*(분|시간|일|주|달|개월)\\s*전$/.test(t)) continue;
            if (t === '어제' || t === '오늘') continue;
            // 지역 (짧은 동/구 이름)
            if (t.endsWith('동') && t.length <= 6) continue;
            title = t;
            break;
        }
        return {
            href: a.href, img: imgSrc, sold,
            title: title ? title.slice(0, 200) : null,
            price, time,
        };
    })
"""


SKIP_PATTERNS = re.compile(
    r'박스|팩|미개봉|일괄|뭉치|벌크|대량|덱\s|덱$|컬렉션|'
    r'\d+\s*장|세트|묶음|모음|쇼케이스|풀세트|미사용|이상의?\s*카드|'
    r'일판|일본판|일어판|북미판|영문판|영판|미판\b|JP판|EN판|'
    r'굿즈|키링|뱃지|피규어|인형|스티커|봉제|아크릴|매트|슬리브|'
    r'닌텐도|3DS|스위치|콘솔|게임기|슈링크|서치팩|서치\s*팩|카트리지|랜덤'
)


def save_items(items: list[dict]):
    conn = psycopg2.connect(**DB)
    cur = conn.cursor()
    ins = skip = no_hash = no_sold = old = box_skip = 0
    now = datetime.now()
    for it in items:
        if not it.get("sold"):
            no_sold += 1
            continue
        # 제목 필터 — 박스/팩/묶음/일판/굿즈
        if SKIP_PATTERNS.search(it.get("title") or ""):
            box_skip += 1
            continue
        days = parse_days_ago(it.get("time"))
        if days is None:
            no_sold += 1
            continue
        if days > CUTOFF_DAYS:
            old += 1
            continue
        href = it.get("href") or ""
        h = hash_from_href(href)
        if not h:
            no_hash += 1
            continue
        traded_at = now - timedelta(days=days)
        try:
            cur.execute("""
                INSERT INTO price_review_queue
                  (source, source_id, raw_title, raw_price, raw_currency,
                   raw_url, image_path, traded_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (source, source_id) DO NOTHING
                RETURNING id
            """, (
                "DAANGN", h, it.get("title"), it.get("price"), "KRW",
                href, it.get("img"), traded_at,
            ))
            if cur.fetchone():
                ins += 1
            else:
                skip += 1
        except Exception as e:
            print(f"  err {h}: {e}", flush=True)
    conn.commit()
    conn.close()
    return {"ins": ins, "skip_dup": skip, "no_hash": no_hash, "no_sold_or_time": no_sold, "old": old, "box_skip": box_skip}


def extract_region_links(page):
    """현재 page에서 region link (동이름-id) 추출."""
    return page.evaluate("""
    () => {
        const out = [];
        const seen = new Set();
        for (const a of document.querySelectorAll('a[href*="/kr/buy-sell/"]')) {
            const href = a.getAttribute('href') || '';
            const m = href.match(/\\?in=([^&-]+)-(\\d+)(?:&|$)/);
            if (!m) continue;
            const name = decodeURIComponent(m[1]);
            const rid = parseInt(m[2]);
            const key = name + '-' + rid;
            if (seen.has(key)) continue;
            seen.add(key);
            out.push([name, rid]);
        }
        return out;
    }
    """)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", choices=["priority", "seoul", "all"], default="priority")
    ap.add_argument("--phase", choices=["1차", "2차", "3차", "all"], default="1차",
                    help="priority source 일 때만 의미. all 이면 모든 phase.")
    ap.add_argument("--no-resume", action="store_true",
                    help="progress 파일 무시하고 처음부터 재실행.")
    args = ap.parse_args()

    t0 = time.time()
    log = open(LOG, "a")
    print(f"=== DAANGN v2 crawl source={args.source} phase={args.phase} BFS={'OFF' if DISABLE_BFS else 'ON'} ===", flush=True)

    seeds = load_seeds(args.source, args.phase)
    print(f"loaded {len(seeds)} seed regions", flush=True)

    completed = set() if args.no_resume else load_progress()
    if completed:
        print(f"resume: {len(completed)} pid already completed, skipping", flush=True)

    visited: set = set()
    queue: list = list(seeds)
    region_count = 0
    max_regions = len(seeds) + 100  # BFS 확장 buffer (DISABLE_BFS=True 면 사실상 len(seeds))
    total_saved = {"ins": 0, "skip_dup": 0, "no_hash": 0, "no_sold_or_time": 0, "old": 0, "box_skip": 0}

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=False)
        ctx = browser.new_context(
            locale="ko-KR",
            viewport={"width": 1280, "height": 1024},
            user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        )
        page = ctx.new_page()
        while queue and region_count < max_regions:
            name, rid = queue.pop(0)
            key = (name, rid)
            if key in visited or rid in completed:
                continue
            visited.add(key)
            region_count += 1
            try:
                items = crawl_region(page, name, rid)
                stats = save_items(items)
                for k, v in stats.items():
                    total_saved[k] = total_saved.get(k, 0) + v
                line = f"[{region_count}/{len(seeds)}] {name}-{rid} crawled={len(items)} saved={stats}"
                print(line, flush=True)
                log.write(line + "\n"); log.flush()
                # progress 파일 update — 중단 후 재시작 시 이 pid skip
                completed.add(rid)
                save_progress(completed)
                # BFS 확장 (DISABLE_BFS=True 면 skip)
                if not DISABLE_BFS:
                    new_regions = extract_region_links(page)
                    added = 0
                    for nm, nrid in new_regions:
                        nkey = (nm, nrid)
                        if nkey not in visited and (nm, nrid) not in [(a, b) for a, b in queue]:
                            queue.append(nkey)
                            added += 1
                    if added:
                        print(f"   +{added} regions in queue (total queue: {len(queue)})", flush=True)
            except Exception as e:
                print(f"  ERR region {name}-{rid}: {e}", flush=True)
                log.write(f"  ERR {name}-{rid}: {e}\n")

        browser.close()
    print(f"DONE in {time.time()-t0:.0f}s: regions={region_count}/{len(seeds)} totals={total_saved}", flush=True)
    log.close()


if __name__ == "__main__":
    main()
