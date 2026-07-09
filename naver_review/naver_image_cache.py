"""NAVER 카페 원문 이미지 캐시 — review_v4용. ★네 Mac Chrome(네이버 로그인)에서 CDP로.
전제: 별도 Chrome 띄우고 네이버 로그인:
  /Applications/Google\\ Chrome.app/Contents/MacOS/Google\\ Chrome \\
    --remote-debugging-port=9223 --user-data-dir=/tmp/chrome_naver_profile
  → 그 창에서 naver.com 로그인 + cafe.naver.com/cardmvk 한 번 들어가두기.

실행:
  python naver_image_cache.py --test 616987     # 글 1개만(다운 안하고 이미지 URL 몇 개 잡히나 확인)
  python naver_image_cache.py                    # data.js url 있는 글 전체 캐시 → images/naver/{psid}_N.jpg
원칙: pstatic CDN 이미지만, 글당 최대 5장, 정중 딜레이. 실패=실패CSV 기록.
"""
import argparse, asyncio, csv, json, logging, os, re, sys, time, urllib.request
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("naver_img")
CDP = "http://localhost:9223"
OUT_IMG = "images/naver"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/149.0.0.0 Safari/537.36"
SCAN_JS = """() => { const u=new Set();
  document.querySelectorAll('img').forEach(i=>{const s=i.currentSrc||i.src||i.getAttribute('data-src')||'';
    if(/pstatic\\.net|cafefiles|postfiles/.test(s) && !/icon|profile|emoticon|blank|btn_|sprite/i.test(s)) u.add(s.replace(/\\?type=.*$/,''));});
  return [...u]; }"""


async def extract(target, url):
    """글 페이지 열고 모든 frame에서 pstatic 이미지 URL 수집."""
    try:
        await target.goto(url, wait_until="domcontentloaded", timeout=20000)
    except Exception as e:
        return None, f"goto_fail:{e}"
    await asyncio.sleep(2.0)
    title = await target.title()
    if "로그인" in (title or "") or "nidlogin" in (target.url or ""):
        return None, "LOGIN_WALL"
    urls = []
    for fr in target.frames:
        try:
            urls += await fr.evaluate(SCAN_JS)
        except Exception:
            pass
    seen, ded = set(), []
    for u in urls:
        if u not in seen:
            seen.add(u); ded.append(u)
    return ded[:5], "OK" if ded else "NO_IMAGE"


def download(u, path):
    try:
        req = urllib.request.Request(u, headers={"User-Agent": UA, "Referer": "https://cafe.naver.com/"})
        with urllib.request.urlopen(req, timeout=15) as r:
            open(path, "wb").write(r.read())
        return True
    except Exception:
        return False


async def amain(a):
    from playwright.async_api import async_playwright
    os.makedirs(OUT_IMG, exist_ok=True)
    async with async_playwright() as pw:
        try:
            browser = await pw.chromium.connect_over_cdp(CDP, timeout=5000)
        except Exception as e:
            log.error("CDP attach 실패(%s). Chrome 9223 + 네이버 로그인 필요.", e); sys.exit(2)
        ctx = browser.contexts[0] if browser.contexts else await browser.new_context()
        page = await ctx.new_page()

        if a.test:  # 단일 테스트 (cardmvk 기준)
            url = a.test if a.test.startswith("http") else f"https://cafe.naver.com/cardmvk/{a.test}"
            log.info("[test] %s", url)
            imgs, st = await extract(page, url)
            log.info("[test] status=%s images=%s", st, len(imgs) if imgs else 0)
            for i, u in enumerate(imgs or []):
                log.info("   img%d: %s", i, u)
            log.info("→ 이미지 URL 잡히면 OK. NO_IMAGE/LOGIN_WALL이면 카페 로그인/구조 문제.")
            return

        posts = [d for d in json.loads(open("data.js").read().split("=", 1)[1].rstrip().rstrip(";")) if d.get("url")]
        if a.limit: posts = posts[:a.limit]
        ok = open("naver_post_cache.csv", "w", newline=""); okw = csv.writer(ok)
        okw.writerow(["psid", "url", "fetch_status", "image_count", "image_cache_paths", "scraped_at"])
        fl = open("naver_image_cache_failed.csv", "w", newline=""); flw = csv.writer(fl)
        flw.writerow(["psid", "url", "error_reason"])
        for n, d in enumerate(posts):
            psid, url = d["psid"], d["url"]
            if all(os.path.exists(f"{OUT_IMG}/{psid}_{i}.jpg") for i in range(1)):  # 이미 0번 있으면 skip
                if os.path.exists(f"{OUT_IMG}/{psid}_0.jpg"): continue
            imgs, st = await extract(page, url)
            if not imgs:
                flw.writerow([psid, url, st]); fl.flush()
            else:
                paths = []
                for i, u in enumerate(imgs):
                    p = f"{OUT_IMG}/{psid}_{i}.jpg"
                    if download(u, p): paths.append(p)
                okw.writerow([psid, url, st, len(paths), "|".join(paths), time.strftime("%Y-%m-%d %H:%M")]); ok.flush()
            if (n + 1) % 20 == 0: log.info("  %d/%d", n + 1, len(posts))
            await asyncio.sleep(1.2 + (n % 3) * 0.4)  # 정중 딜레이
        log.info("[done] %d posts", len(posts))


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--test"); ap.add_argument("--limit", type=int)
    asyncio.run(amain(ap.parse_args()))
