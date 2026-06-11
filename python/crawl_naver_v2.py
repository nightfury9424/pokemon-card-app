"""NAVER 카페 경매 v2 — menu 28 + 63 BFS, 60일 cutoff, 검수 큐 적재.

필터:
- 제외: 일판/북미판/띠부씰/등급(PSA/BRG/CGC/BGS/SGC)/박스/묶음
- 통과: 한국 RAW 단일 카드만

낙찰가:
- 대댓글에 "낙찰" → 그 refId 댓글의 가격

저장:
- price_review_queue (source=NAVER_CAFE, source_id=articleId)
- raw_url, raw_title (subject), image_path, traded_at, raw_price
- 자동 분류는 별도 step (DINOv2)
"""
from __future__ import annotations
import json
import logging
import re
import time
from datetime import datetime, timedelta
from pathlib import Path

import psycopg2
import requests

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
log = logging.getLogger(__name__)

DB = {"dbname": "pokemon_card_db", "user": "nightfury"}
CAFE_ID = 30418914
MENUS = [28, 63]  # 종료된 카드 경매 + 진행 중/다른 메뉴
DAYS = 60
HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://cafe.naver.com/cardmvk',
    'Accept-Language': 'ko-KR,ko;q=0.9',
}
LIST_URL = 'https://apis.naver.com/cafe-web/cafe2/ArticleListV2.json'
ARTICLE_URL = f'https://apis.naver.com/cafe-web/cafe-articleapi/v2.1/cafes/{CAFE_ID}/articles/{{}}'

IMG_DIR = Path("/Users/fury/pokemon-card-app/scanner/data/crawl_raw/images_naver")
IMG_DIR.mkdir(parents=True, exist_ok=True)
LOG = Path("/tmp/crawl_naver_v2.log")

# 필터 패턴
NON_KO = re.compile(r'일판|일본판|일어판|북미판|북미|영문판|영판|미판|jp판|en판|미국판', re.I)
TIBU = re.compile(r'띠부씰|띠부실|띠부|포켓몬빵|스티커')
GRADED = re.compile(r'\b(PSA|BGS|BRG|CGC|SGC|PCG)\s*\d+\.?\d*\b|psa\d|brg\d|cgc\d', re.I)
BUNDLE = re.compile(r'박스|미개봉|일괄|뭉치|싱글\s*\d+|싱글총|묶음|벌크|N장|\d+\s*장(?!\s*카드)|개봉\s*\d+장')
PRICE_NUM = re.compile(r'(\d{1,3}(?:[,\s]?\d{3})+|\d{4,})\s*원?')


def should_skip(subject: str) -> tuple[bool, str]:
    """제목 기반 필터. (skip, reason) 반환."""
    if NON_KO.search(subject): return True, "non_ko"
    if TIBU.search(subject): return True, "tibu"
    if GRADED.search(subject): return True, "graded"
    if BUNDLE.search(subject): return True, "bundle"
    return False, ""


def fetch_list(menu_id: int, page: int) -> list[dict]:
    params = {
        'search.clubid': CAFE_ID,
        'search.menuid': menu_id,
        'search.page': page,
        'search.perPage': 50,
    }
    try:
        r = requests.get(LIST_URL, params=params, headers=HEADERS, timeout=15)
        r.raise_for_status()
        return r.json()['message']['result'].get('articleList', [])
    except Exception as e:
        log.warning(f'list fetch fail menu={menu_id} page={page}: {e}')
        return []


def fetch_article(aid: int) -> dict | None:
    try:
        r = requests.get(ARTICLE_URL.format(aid), headers=HEADERS, timeout=15)
        r.raise_for_status()
        return r.json().get('result')
    except Exception:
        return None


def parse_winning_price(comments_items: list) -> int | None:
    """대댓글 중 '낙찰' 포함 → refId 댓글 내용에서 가격 추출."""
    if not comments_items:
        return None
    id_to_content = {c['id']: c.get('content', '') for c in comments_items}
    for c in comments_items:
        if c.get('id') != c.get('refId') and '낙찰' in (c.get('content') or ''):
            winning = id_to_content.get(c['refId'], '')
            m = PRICE_NUM.search(winning)
            if m:
                num = m.group(1).replace(',', '').replace(' ', '')
                try:
                    return int(num)
                except Exception:
                    pass
    return None


def first_image(article_data: dict) -> str | None:
    if not article_data:
        return None
    art = article_data.get('article') or {}
    imgs = art.get('attachImage') or []
    if imgs and isinstance(imgs, list):
        first = imgs[0]
        if isinstance(first, dict):
            return first.get('url')
        return first
    html = art.get('contentHtml') or ''
    m = re.search(r'<img[^>]+src="([^"]+)"', html)
    return m.group(1) if m else None


def download_image(url: str, dst: Path) -> bool:
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.raise_for_status()
        dst.write_bytes(r.content)
        return True
    except Exception:
        return False


def main():
    cutoff = datetime.now() - timedelta(days=DAYS)
    log_f = LOG.open("w")
    conn = psycopg2.connect(**DB)
    cur = conn.cursor()

    stats = {"ok": 0, "skip_subject": 0, "no_winning": 0,
             "fetch_fail": 0, "old": 0, "dup": 0, "err": 0}
    skip_reasons: dict[str, int] = {}

    t0 = time.time()
    for menu_id in MENUS:
        log.info(f'=== menu {menu_id} ===')
        page = 1
        stop_menu = False
        while not stop_menu:
            items = fetch_list(menu_id, page)
            if not items:
                break
            log.info(f'  page {page}: {len(items)} articles')

            for it in items:
                subject = it.get('subject') or ''
                comment_count = it.get('commentCount') or 0
                article_id = it.get('articleId')
                if not article_id:
                    continue
                # 1차 제목 검열
                skip, reason = should_skip(subject)
                if skip:
                    stats["skip_subject"] += 1
                    skip_reasons[reason] = skip_reasons.get(reason, 0) + 1
                    continue
                if comment_count == 0:
                    continue

                time.sleep(0.25)
                data = fetch_article(article_id)
                if not data:
                    stats["fetch_fail"] += 1
                    continue

                art = data.get('article') or {}
                write_ts = art.get('writeDate', 0) / 1000
                write_dt = datetime.fromtimestamp(write_ts)
                if write_dt < cutoff:
                    log.info(f'  cutoff reached at article {article_id} ({write_dt.date()})')
                    stop_menu = True
                    break

                # 낙찰가 추출
                comments = data.get('comments', {}).get('items', [])
                winning = parse_winning_price(comments)
                if not winning or winning < 100:
                    stats["no_winning"] += 1
                    continue

                # 첫 이미지 다운로드
                img_path_rel = None
                local_img = IMG_DIR / f"{article_id}.jpg"
                if not local_img.exists():
                    url = first_image(data)
                    if url and download_image(url, local_img):
                        img_path_rel = f"crawl_raw/images_naver/{article_id}.jpg"
                else:
                    img_path_rel = f"crawl_raw/images_naver/{article_id}.jpg"

                try:
                    cur.execute("""
                        INSERT INTO price_review_queue
                          (source, source_id, raw_title, raw_price, raw_currency,
                           raw_url, image_path, traded_at)
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (source, source_id) DO NOTHING
                        RETURNING id
                    """, (
                        "NAVER_CAFE", str(article_id), subject, winning, "KRW",
                        f"https://cafe.naver.com/cardmvk/{article_id}",
                        img_path_rel, write_dt,
                    ))
                    if cur.fetchone():
                        stats["ok"] += 1
                        if stats["ok"] % 10 == 0:
                            conn.commit()
                            log.info(f'  ok={stats["ok"]} skip={stats["skip_subject"]} no_win={stats["no_winning"]}')
                    else:
                        stats["dup"] += 1
                except Exception as e:
                    stats["err"] += 1
                    log_f.write(f'  err {article_id}: {e}\n')

            page += 1
            if page > 60:  # safety cap
                log.warning(f'  page cap reached menu={menu_id}')
                break

    conn.commit()
    conn.close()
    el = time.time() - t0
    summary = f'DONE in {el:.0f}s: {stats} skip_reasons={skip_reasons}'
    log.info(summary)
    log_f.write(summary + "\n")
    log_f.close()


if __name__ == "__main__":
    main()
