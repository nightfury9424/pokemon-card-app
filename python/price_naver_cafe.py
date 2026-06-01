#!/usr/bin/env python3
"""
naver_cafe_auction_scraper.py — 포켓몬카드 MVC 카페 경매 낙찰가 수집
카페: https://cafe.naver.com/cardmvk (cafeId=30418914, menuId=28)

날짜 제한: --days 옵션으로 최근 N일 이내 게시글만 수집 (기본 60일)
가격 활용: 30일 이내 낙찰가 중앙값 → KO 실거래가로 사용
"""

import re
import time
import json
import uuid
import logging
import argparse
from datetime import datetime, timedelta
from typing import Optional

import psycopg2
import requests

# Phase 0b: 산출 시점 ratio guard와 동일 임계값 재사용 (drift 방지)
from recalc_coefficients import RATIO_FLOOR, RATIO_CEILING, get_exchange_rates

logging.basicConfig(level=logging.INFO, format='[%(levelname)s] %(message)s')
log = logging.getLogger(__name__)

from config import get_db_dsn  # Phase 1-4: env 기반 DSN
DB_DSN = get_db_dsn()
CAFE_ID = 30418914
MENU_ID = 28  # 종료된 카드 경매

LIST_URL = 'https://apis.naver.com/cafe-web/cafe2/ArticleListV2.json'
ARTICLE_URL = f'https://apis.naver.com/cafe-web/cafe-articleapi/v2.1/cafes/{CAFE_ID}/articles/{{articleId}}'

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://cafe.naver.com/cardmvk',
    'Accept-Language': 'ko-KR,ko;q=0.9',
}

RARITY_KEYWORDS = ['bwr', 'mur', 'sar', 'ssr', 'shr', 'chr', 'ur', 'hr', 'ar', 'rr', 'sr', 'r', 'ma', 'rpa', 'k']
GRADING_PATTERN = re.compile(r'\b(psa|bgs|brg|sgc|cgc)\s*(\d+\.?\d*)\b', re.IGNORECASE)

# 번들/일괄 경매 스킵 패턴 (단일 카드가 아님)
BUNDLE_PATTERN = re.compile(r'총\s*\d+\s*종|일괄|뭉치|싱글\s*\d+|싱글총|묶음', re.IGNORECASE)
# 일판/북미판 등 비한국 카드 경매 스킵 (KO 카드 가격 오염 방지)
NON_KO_PATTERN = re.compile(r'일판|일본판|일어판|북미판|북미|jp판|미판|영판', re.IGNORECASE)


def fetch_article_list(page: int, per_page: int = 50) -> dict:
    params = {
        'search.clubid': CAFE_ID,
        'search.menuid': MENU_ID,
        'search.page': page,
        'search.perPage': per_page,
    }
    r = requests.get(LIST_URL, params=params, headers=HEADERS, timeout=15)
    r.raise_for_status()
    return r.json()['message']['result']


def fetch_article(article_id: int) -> Optional[dict]:
    """기존 호환 — result만 반환."""
    url = ARTICLE_URL.format(articleId=article_id)
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.raise_for_status()
        return r.json()['result']
    except Exception as e:
        log.warning(f'article {article_id} fetch 실패: {e}')
        return None


# NAVER API 댓글 페이지 한계 — 첫 페이지 10개만 반환. 페이징 spec 비공개.
COMMENT_PAGE_LIMIT = 10


def fetch_article_with_truncation(article_id: int) -> tuple:
    """article result + truncated flag. comments >= COMMENT_PAGE_LIMIT면 truncated.

    2026-05-19 보강: 댓글 페이징 미처리 — 10개 이상이면 실제 낙찰가가 뒤에 있을 수 있음.
    truncated=True인 row는 auto_price_suspect=True로 표시해 사용자 검수 시 가격 수동 수정 유도.
    """
    url = ARTICLE_URL.format(articleId=article_id)
    try:
        r = requests.get(url, headers=HEADERS, timeout=15)
        r.raise_for_status()
        result = r.json()['result']
        items = result.get('comments', {}).get('items', [])
        truncated = len(items) >= COMMENT_PAGE_LIMIT
        return result, truncated
    except Exception as e:
        log.warning(f'article {article_id} fetch 실패: {e}')
        return None, False


def extract_image_url(content_html: str) -> Optional[str]:
    """article.contentHtml에서 첫 번째 se-image-resource img src 추출.

    NAVER 카페 본문 이미지: <img class="se-image-resource" src="https://cafeptthumb-phinf.pstatic.net/...">
    """
    if not content_html:
        return None
    match = re.search(
        r'<img[^>]*class="[^"]*se-image-resource[^"]*"[^>]*src="([^"]+)"',
        content_html, re.IGNORECASE)
    if match:
        return match.group(1)
    # 폴백 — 일반 pstatic.net 이미지
    match = re.search(r'<img[^>]+src="(https://[^"]*pstatic\.net[^"]+)"', content_html)
    if match:
        return match.group(1)
    return None


def extract_winning_price_v2(comments: list) -> tuple:
    """기존 winning_price 추출 + 모든 가격 후보 리스트 반환.

    log에 후보 출력 — truncated 시 사용자가 검수에서 판단 가능.
    """
    candidates = []
    for c in comments:
        price = parse_price(c.get('content', ''))
        if price and price > 1000:
            candidates.append(price)

    if not comments:
        return None, candidates

    # 1순위: "낙찰" reply의 refId 댓글 가격
    id_to_content = {c['id']: c.get('content', '') for c in comments}
    for c in comments:
        if c['id'] != c['refId'] and '낙찰' in c['content']:
            winning_content = id_to_content.get(c['refId'], '')
            p = parse_price(winning_content)
            if p and p > 1000:
                return p, candidates

    # 2순위: 마지막 유효 입찰가 (root 댓글)
    last_price = None
    for c in comments:
        if c['id'] == c['refId']:
            p = parse_price(c.get('content', ''))
            if p and p > 1000:
                last_price = p
    return last_price, candidates


def extract_winning_price(comments: list) -> Optional[int]:
    """
    '낙찰' 포함 대댓글의 refId → 낙찰된 입찰 댓글 → 가격 추출
    """
    if not comments:
        return None

    id_to_content = {c['id']: c.get('content', '') for c in comments}

    for c in comments:
        if c['id'] != c['refId'] and '낙찰' in c['content']:
            winning_content = id_to_content.get(c['refId'], '')
            price = parse_price(winning_content)
            if price and price > 1000:
                return price

    # 폴백: 마지막 유효 입찰가
    last_price = None
    for c in comments:
        if c['id'] == c['refId']:
            price = parse_price(c.get('content', ''))
            if price and price > 1000:
                last_price = price
    return last_price


def parse_price(text: str) -> Optional[int]:
    text = text.strip().replace(',', '').replace(' ', '')
    m = re.match(r'^(\d+)원?$', text)
    if m:
        return int(m.group(1))
    m = re.search(r'\b(\d{4,7})\b', text)
    if m:
        return int(m.group(1))
    return None


def count_rarity_keywords(subject: str) -> int:
    """제목에서 레어도 키워드가 몇 개 등장하는지 카운트 (번들 감지용)"""
    s = subject.lower()
    found = set()
    for r in sorted(RARITY_KEYWORDS, key=len, reverse=True):
        if re.search(r'\b' + re.escape(r) + r'\b', s):
            found.add(r)
            # 이미 찾은 키워드 제거해서 중복 카운트 방지
            s = re.sub(r'\b' + re.escape(r) + r'\b', '', s)
    return len(found)


def parse_subject(subject: str) -> dict:
    s = subject.lower()

    # 날짜/마감 제거
    s = re.sub(r'\(?\d+/\d+[가-힣\s]*\)?', '', s)
    s = re.sub(r'\(?\d+월\s*\d+일[가-힣\s]*\)?', '', s)
    s = re.sub(r'\[.*?\]', '', s)
    s = re.sub(r'마감|카드\s*경매|경매|싱글|미개봉|스페셜|한판|클버|일본판|북미판|특일|연번|고대카드', '', s)
    s = re.sub(r'(upc|프로모|프로|rpa\d*)', '', s)
    s = s.strip()

    # 등급 파싱
    grade_m = GRADING_PATTERN.search(s)
    grade = grade_m.group(1).upper() if grade_m else None
    grade_val = grade_m.group(2) if grade_m else None
    if grade_m:
        s = s[:grade_m.start()] + s[grade_m.end():]

    # 레어도 추출 (긴 것 우선)
    rarity = None
    for r in sorted(RARITY_KEYWORDS, key=len, reverse=True):
        if re.search(r'\b' + re.escape(r) + r'\b', s):
            rarity = r.upper()
            s = re.sub(r'\b' + re.escape(r) + r'\b', '', s)
            break

    # 출처 표시 제거
    s = re.sub(r'\b(북미|일판|한판|특일|싱글)\b', '', s)

    # 키워드 추출
    words = [w.strip() for w in re.split(r'[\s,&+/\(\)\'\"]+', s) if len(w.strip()) >= 2]
    words = [w for w in words if not re.match(r'^\d+$', w)]

    return {
        'name_keywords': words,
        'rarity': rarity,
        'grade_company': grade,
        'grade_value': grade_val,
    }


def find_card_match(conn, keywords: list, rarity: Optional[str]) -> Optional[str]:
    if not keywords:
        return None

    with conn.cursor() as cur:
        for kw in sorted(keywords, key=len, reverse=True):
            if len(kw) < 2:
                continue
            if rarity:
                # 레어도 명시된 경우: 레어도 + 이름으로 엄격히 매칭
                cur.execute("""
                    SELECT card_id FROM cards
                    WHERE name ILIKE %s AND rarity_code = %s
                    LIMIT 10
                """, (f'%{kw}%', rarity))
            else:
                cur.execute("""
                    SELECT card_id, rarity_code FROM cards
                    WHERE name ILIKE %s
                    LIMIT 10
                """, (f'%{kw}%',))

            rows = cur.fetchall()
            if len(rows) == 1:
                return rows[0][0]
            if 1 < len(rows) <= 10:
                # 레어도 미지정: 여러 레어도가 섞여있으면 스킵 (오염 방지)
                if not rarity:
                    rarities = {r[1] for r in rows}
                    if len(rarities) > 1:
                        continue  # 레어도 특정 불가 → 스킵

                card_ids = [r[0] for r in rows]
                for kw2 in keywords:
                    if kw2 == kw:
                        continue
                    cur.execute("""
                        SELECT card_id FROM cards
                        WHERE card_id = ANY(%s) AND name ILIKE %s
                    """, (card_ids, f'%{kw2}%'))
                    narrow = cur.fetchall()
                    if len(narrow) == 1:
                        return narrow[0][0]

    return None


def fetch_ko_estimated(conn, card_id: str) -> Optional[int]:
    """DB에서 해당 카드의 KO_ESTIMATED 최신값 조회 (가격 검열용)"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT price FROM price_snapshots
            WHERE card_id = %s AND source = 'KO_ESTIMATED'
            ORDER BY traded_at DESC
            LIMIT 1
        """, (card_id,))
        row = cur.fetchone()
        return row[0] if row else None


def already_saved(conn, card_id: str, traded_at: datetime) -> bool:
    """같은 날짜 같은 카드의 NAVER_CAFE 스냅샷 중복 방지 (legacy 호환)"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT 1 FROM price_snapshots
            WHERE card_id = %s AND source = 'NAVER_CAFE'
            AND DATE(traded_at) = %s
            LIMIT 1
        """, (card_id, traded_at.date()))
        return cur.fetchone() is not None


def already_saved_by_source_id(conn, source_id: str) -> bool:
    """source_item_id 기준 중복 방지 (article_id 단위, 검수 큐와 일관)"""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT 1 FROM price_snapshots
            WHERE source = 'NAVER_CAFE' AND source_item_id = %s
            LIMIT 1
        """, (source_id,))
        return cur.fetchone() is not None


def fetch_scrydex_krw(conn, card_id: str, exchange_rates: dict) -> Optional[float]:
    """카드의 latest SCRYDEX_JP raw price를 KRW로 환산. JP 우선, 없으면 EN."""
    with conn.cursor() as cur:
        cur.execute("""
            SELECT raw_price, raw_currency
            FROM price_snapshots
            WHERE card_id = %s
              AND source IN ('SCRYDEX_JP','SCRYDEX_EN')
              AND card_status = 'RAW'
              AND raw_price IS NOT NULL
              AND raw_currency IN ('USD','JPY')
            ORDER BY (source='SCRYDEX_JP') DESC, traded_at DESC
            LIMIT 1
        """, (card_id,))
        row = cur.fetchone()
    if not row:
        return None
    raw_price, currency = row
    if currency == 'USD':
        return float(raw_price) * exchange_rates['USD']
    if currency == 'JPY':
        return float(raw_price) * exchange_rates['JPY']
    return None


def classify_naver_price(naver_price: int, scrydex_krw: Optional[float]) -> tuple:
    """수집된 NAVER 낙찰가를 ratio guard로 분류.

    반환: (validation_status, invalid_reason)
    - SCRYDEX 미존재 → PENDING_REVIEW (수동 검수 필요, 자동 분류 불가)
    - ratio < RATIO_FLOOR → INVALID + reason
    - ratio > RATIO_CEILING → INVALID + reason
    - 정상 범위 → PENDING_REVIEW (검수 통과 시 VALID 승격)

    INSERT 절대 default 'VALID' 안 들어감. 검수 흐름 반드시 통과해야 substrate 진입.
    """
    if not scrydex_krw or scrydex_krw <= 0:
        return ('PENDING_REVIEW', 'no_scrydex_reference')
    ratio = naver_price / scrydex_krw
    if ratio < RATIO_FLOOR:
        return ('INVALID', f'ratio_too_low:{ratio:.4f}')
    if ratio > RATIO_CEILING:
        return ('INVALID', f'ratio_too_high:{ratio:.4f}')
    return ('PENDING_REVIEW', None)


def save_or_update_price(conn, card_id: str, price: int, card_status: str,
                         grading_company: Optional[str], grade_value: Optional[str],
                         traded_at: datetime,
                         raw_title: str, source_url: str, source_item_id: str,
                         raw_price: int,
                         validation_status: str = 'PENDING_REVIEW',
                         invalid_reason: Optional[str] = None):
    """price_snapshots upsert (source_item_id 기준).

    2026-05-19 보강 — parser fix 시 재수집할 때 같은 source_item_id row를 UPDATE할 수 있게.
    - VALID 검수 완료 row는 건드리지 않음 (사용자 결정 보존)
    - PENDING_REVIEW / INVALID는 새 parser 결과로 UPDATE
    """
    with conn.cursor() as cur:
        cur.execute("""
            SELECT price_snapshot_id, validation_status
            FROM price_snapshots
            WHERE source='NAVER_CAFE' AND source_item_id=%s
            LIMIT 1
        """, (source_item_id,))
        row = cur.fetchone()
        if row:
            sid, existing_status = row
            if existing_status == 'VALID':
                # 사용자가 verify한 row — parser 재수집에서 건드리지 않음
                return None
            # PENDING_REVIEW / INVALID → UPDATE
            cur.execute("""
                UPDATE price_snapshots SET
                    card_id=%s, price=%s, raw_price=%s,
                    title=%s, source_url=%s,
                    card_status=%s, grading_company=%s, grade_value=%s,
                    traded_at=%s,
                    validation_status=%s, invalid_reason=%s
                WHERE price_snapshot_id=%s
            """, (card_id, price, raw_price, raw_title, source_url,
                  card_status, grading_company, grade_value, traded_at,
                  validation_status, invalid_reason, sid))
            conn.commit()
            return sid
        # 신규
        snap_id = uuid.uuid4().hex
        cur.execute("""
            INSERT INTO price_snapshots
              (price_snapshot_id, card_id, source, source_item_id, source_url,
               price, raw_price, raw_currency, title, card_status,
               grading_company, grade_value, traded_at, collected_at,
               validation_status, invalid_reason)
            VALUES (%s, %s, 'NAVER_CAFE', %s, %s,
                    %s, %s, 'KRW', %s, %s,
                    %s, %s, %s, NOW(),
                    %s, %s)
        """, (snap_id, card_id, source_item_id, source_url,
              price, raw_price, raw_title, card_status,
              grading_company, grade_value, traded_at,
              validation_status, invalid_reason))
        conn.commit()
        return snap_id


# 기존 함수 호환용 alias (다른 곳에서 호출하면 새 시그니처로 동작)
save_price = save_or_update_price


def save_to_review_queue(conn, source_id: str, raw_title: str, raw_price: int,
                         raw_url: str, traded_at: datetime, card_id: str,
                         image_path: Optional[str] = None,
                         auto_price_suspect: bool = False):
    """NAVER_CAFE PENDING_REVIEW를 검수 큐(price_review_queue)에 upsert.

    UNIQUE(source, source_id) — 같은 article은 항상 한 row.
    parser fix 후 재수집 시 raw_title/price/image/suspect 새로 갱신.
    reviewed_at, rejection_reason은 NULL로 초기화 (재검수 대상).
    """
    auto_candidates = [{"card_id": card_id, "confidence": 1.0}]
    with conn.cursor() as cur:
        cur.execute("""
            INSERT INTO price_review_queue
              (source, source_id, raw_title, raw_price, raw_currency,
               raw_url, image_path, traded_at, auto_candidates,
               auto_price_suspect, status)
            VALUES ('NAVER_CAFE', %s, %s, %s, 'KRW',
                    %s, %s, %s, %s::jsonb,
                    %s, 'pending')
            ON CONFLICT (source, source_id) DO UPDATE SET
              raw_title = EXCLUDED.raw_title,
              raw_price = EXCLUDED.raw_price,
              raw_url = EXCLUDED.raw_url,
              image_path = EXCLUDED.image_path,
              traded_at = EXCLUDED.traded_at,
              auto_candidates = EXCLUDED.auto_candidates,
              auto_price_suspect = EXCLUDED.auto_price_suspect,
              status = 'pending',
              reviewed_at = NULL,
              rejection_reason = NULL
        """, (source_id, raw_title, int(raw_price), raw_url, image_path, traded_at,
              json.dumps(auto_candidates), auto_price_suspect))
    conn.commit()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--days', type=int, default=60,
                        help='최근 N일 이내 게시글만 수집 (기본 60일, 오래된 가격은 신뢰 불가)')
    parser.add_argument('--max-pages', type=int, default=200,
                        help='최대 페이지 수 (기본 200)')
    parser.add_argument('--dry-run', action='store_true',
                        help='DB 저장 없이 파싱 결과만 출력')
    args = parser.parse_args()

    cutoff = datetime.now() - timedelta(days=args.days)
    log.info(f'수집 기준: {cutoff.date()} 이후 ({args.days}일 이내) 게시글만')

    conn = psycopg2.connect(DB_DSN) if not args.dry_run else None

    # Phase 0b: 환율 1회 조회 (ratio guard용)
    exchange_rates = get_exchange_rates(conn) if conn else None
    if exchange_rates:
        log.info(f'환율 USD={exchange_rates["USD"]:.0f} JPY={exchange_rates["JPY"]:.2f}')

    total = 0
    matched = 0
    skipped_bundle = 0
    skipped_old = 0
    skipped_price = 0
    no_price = 0
    unmatched = []

    for page in range(1, args.max_pages + 1):
        log.info(f'--- 페이지 {page} ---')
        try:
            result = fetch_article_list(page)
        except Exception as e:
            log.error(f'목록 수집 실패: {e}')
            break

        articles = result.get('articleList', [])
        if not articles:
            log.info('더 이상 게시글 없음')
            break

        reached_cutoff = False
        for art in articles:
            article_id = art['articleId']
            subject = art['subject']
            comment_count = art.get('commentCount', 0)

            # 일판/북미판 스킵 (KO 카드 가격 오염 방지)
            if NON_KO_PATTERN.search(subject):
                log.debug(f'  비한국 카드 스킵: {subject}')
                skipped_bundle += 1
                continue

            # 번들 경매 스킵 1: 명시적 번들 키워드
            if BUNDLE_PATTERN.search(subject) and '싱글' not in subject.split('총')[0]:
                skipped_bundle += 1
                continue

            # 번들 경매 스킵 2: 제목에 레어도 키워드 2개 이상 → 여러 카드 묶음
            if count_rarity_keywords(subject) >= 2:
                log.debug(f'  번들 스킵 (레어도 2개+): {subject}')
                skipped_bundle += 1
                continue

            if comment_count == 0:
                continue

            time.sleep(0.25)
            data, truncated = fetch_article_with_truncation(article_id)
            if not data:
                continue

            write_ts = data['article'].get('writeDate', 0) / 1000
            write_dt = datetime.fromtimestamp(write_ts)

            if write_dt < cutoff:
                log.info(f'  {cutoff.date()} 이전 도달 ({write_dt.date()}) → 수집 종료')
                reached_cutoff = True
                break

            total += 1
            comments = data.get('comments', {}).get('items', [])
            winning_price, price_candidates = extract_winning_price_v2(comments)
            content_html = data.get('article', {}).get('contentHtml', '')
            image_url = extract_image_url(content_html)
            # truncated → 댓글 페이징 한계로 실제 낙찰가 후보 누락 가능 → 검수 시 suspect 표시
            auto_price_suspect = truncated

            if not winning_price:
                no_price += 1
                continue

            parsed = parse_subject(subject)
            rarity = parsed['rarity']
            grade = parsed['grade_company']
            grade_val = parsed['grade_value']
            keywords = parsed['name_keywords']
            card_status = 'GRADED' if grade else 'RAW'

            log.info(f'[{article_id}] {subject}')
            log.info(f'  낙찰가: {winning_price:,}원 | 레어도:{rarity} | 등급:{grade}{grade_val or ""} | 키워드:{keywords}')

            if conn:
                card_id = find_card_match(conn, keywords, rarity)
                if card_id:
                    # 1차 검열: KO_ESTIMATED 대비 ±5배 outlier → SKIP (저장 안 함, 큰 outlier 차단)
                    ko_est = fetch_ko_estimated(conn, card_id)
                    if ko_est:
                        if winning_price < ko_est * 0.2 or winning_price > ko_est * 5.0:
                            log.info(f'  → 가격 검열 스킵: {winning_price:,}원 (KO_EST={ko_est:,}원)')
                            skipped_price += 1
                            continue

                    # 2차 분류: SCRYDEX ratio guard → PENDING_REVIEW / INVALID 분류 (Phase 0b)
                    scrydex_krw = fetch_scrydex_krw(conn, card_id, exchange_rates)
                    validation_status, invalid_reason = classify_naver_price(winning_price, scrydex_krw)

                    article_url = f'https://cafe.naver.com/cardmvk/{article_id}'
                    source_id = str(article_id)

                    # upsert — VALID(사용자 검수 완료)는 보존, PENDING/INVALID는 새 parser 결과로 UPDATE
                    snap_id = save_or_update_price(
                        conn, card_id, winning_price, card_status,
                        grade, grade_val, write_dt,
                        raw_title=subject,
                        source_url=article_url,
                        source_item_id=source_id,
                        raw_price=winning_price,
                        validation_status=validation_status,
                        invalid_reason=invalid_reason)
                    if snap_id is None:
                        log.debug(f'  → VALID 보존 스킵: {source_id}')
                    else:
                        suspect_tag = ' [SUSPECT]' if auto_price_suspect else ''
                        log.info(f'  → 저장 [{validation_status}{suspect_tag}'
                                 f'{" reason=" + invalid_reason if invalid_reason else ""}]: {card_id}'
                                 f' | 가격 후보 {price_candidates}')
                        # PENDING_REVIEW만 검수 큐에 적재 + UPDATE (INVALID는 큐 불필요)
                        if validation_status == 'PENDING_REVIEW':
                            save_to_review_queue(
                                conn, source_id, subject, winning_price,
                                article_url, write_dt, card_id,
                                image_path=image_url,
                                auto_price_suspect=auto_price_suspect)
                            log.info(f'  → 검수 큐 upsert: {source_id}'
                                     f' suspect={auto_price_suspect} img={"O" if image_url else "X"}')
                    matched += 1
                else:
                    unmatched.append(f'{subject} | {winning_price:,}원 | kw:{keywords} | r:{rarity}')
            else:
                # dry-run: 매칭 시뮬레이션
                matched += 1

        if reached_cutoff:
            break

    log.info(f'\n=== 완료 ===')
    log.info(f'처리: {total}건 | 매칭 저장: {matched}건 | 번들 스킵: {skipped_bundle}건 | 가격 검열 스킵: {skipped_price}건 | 낙찰가 없음: {no_price}건')
    if unmatched:
        log.info(f'\n미매칭 {len(unmatched)}건 (상위 30):')
        for s in unmatched[:30]:
            log.info(f'  {s}')

    if conn:
        conn.close()


if __name__ == '__main__':
    main()
