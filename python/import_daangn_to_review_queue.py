#!/usr/bin/env python3
"""당근(crawl_results_daangn.json) → price_review_queue import.

2026-05-19 — NAVER 보류, 당근 검수 파이프라인 활성화.
기존 verified/rejected 1,750건은 ON CONFLICT DO NOTHING으로 보존.

사용:
  python3 python/import_daangn_to_review_queue.py --dry-run   # 통계만
  python3 python/import_daangn_to_review_queue.py             # 실제 import
"""
import argparse
import json
import re
from pathlib import Path

import psycopg2

DB_DSN = 'host=localhost port=5432 dbname=pokemon_card_db user=nightfury'
JSON_PATH = (Path(__file__).parent.parent
             / 'scanner/data/crawl_raw/crawl_results_daangn.json')


def parse_price(s):
    if s is None:
        return None
    s = str(s).replace(',', '').strip()
    if not s.isdigit():
        return None
    v = int(s)
    # 1원 같은 무의미 가격 차단 (당근에 "1원 책정" 광고성 게시글 多)
    if v < 1000:
        return None
    return v


def url_for(pid):
    return f'https://www.daangn.com/articles/{pid}'


def main(dry_run=False):
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        entries = json.load(f)
    print(f'JSON: {JSON_PATH}')
    print(f'전체 entries: {len(entries)}')

    stats = {
        'considered': 0,
        'inserted': 0,
        'skip_already_exists': 0,
        'skip_invalid_price': 0,
        'skip_no_candidates': 0,
        'skip_labeled_not_none': 0,
        'missing_image_but_inserted': 0,
    }
    samples = []

    conn = psycopg2.connect(DB_DSN)
    cur = conn.cursor()

    for e in entries:
        pid = e.get('pid')
        title = e.get('title', '') or ''
        price_raw = e.get('price', '')
        image_path = e.get('image_path', '') or ''
        candidates = e.get('candidates', []) or []
        label = e.get('label')

        # 1. label 검사 — None 또는 'NONE'만 pending 대상
        if label and label != 'NONE':
            stats['skip_labeled_not_none'] += 1
            continue

        # 2. 가격
        price = parse_price(price_raw)
        if price is None:
            stats['skip_invalid_price'] += 1
            continue

        # 3. 후보 카드 — 없으면 검수 어려움. skip
        auto_cands = [
            {'card_id': c.get('card_id'), 'confidence': 1.0,
             'name': c.get('name', ''), 'rarity': c.get('rarity', '')}
            for c in candidates if c.get('card_id')
        ]
        if not auto_cands:
            stats['skip_no_candidates'] += 1
            continue

        stats['considered'] += 1
        if not image_path:
            stats['missing_image_but_inserted'] += 1

        if dry_run:
            if len(samples) < 5:
                samples.append({
                    'pid': pid,
                    'title': title[:40],
                    'price': price,
                    'image': image_path or '(none)',
                    'cands': len(auto_cands),
                })
            continue

        cur.execute("""
            INSERT INTO price_review_queue
              (source, source_id, raw_title, raw_price, raw_currency,
               raw_url, image_path, auto_candidates, status)
            VALUES ('DAANGN', %s, %s, %s, 'KRW',
                    %s, %s, %s::jsonb, 'pending')
            ON CONFLICT (source, source_id) DO NOTHING
            RETURNING id
        """, (pid, title, price, url_for(pid),
              image_path or None, json.dumps(auto_cands)))
        result = cur.fetchone()
        if result:
            stats['inserted'] += 1
        else:
            stats['skip_already_exists'] += 1

    if not dry_run:
        conn.commit()
    conn.close()

    print()
    print('=== Stats ===')
    for k, v in stats.items():
        print(f'  {k}: {v}')

    if dry_run and samples:
        print()
        print('=== Sample (first 5) ===')
        for s in samples:
            print(f'  {s}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()
    main(dry_run=args.dry_run)
