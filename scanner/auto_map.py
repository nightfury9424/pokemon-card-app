#!/usr/bin/env python3
"""NO_ 처리된 카드들에 scrydex ref 자동 제안 → auto_map_suggestions.json"""
import json, re, requests
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

SCANNER = "http://localhost:8082"
DATA_DIR = Path(__file__).parent / "data"

with open(DATA_DIR / "ko_en_pokemon.json", encoding="utf-8") as f:
    KO_EN_MAP = json.load(f)

KO_HINT_EXTRA = {
    '루나알라':'lunala','소루가레오':'solgaleo','루나아라':'lunala',
    '에브이':'eevee','마리찌':'marill','마릴':'marill',
    '카푸꼬꼬꼭':'tapu koko','카푸나비나':'tapu lele',
    '카푸브루루':'tapu bulu','카푸느자느':'tapu fini',
    '백마 버드렉스':'calyrex','흑마 버드렉스':'calyrex',
    '요씽리스':'galarian slowbro','파이어':'flareon','에레브':'electabuzz',
    '지우개굴닌자':'greninja','라이치':'olivia',
}
KO_PREFIXES = ['블랙', '화이트', '메가', '기가', '섀도', 'M']
RARITY_HINT = {
    'SAR':'illustration rare','SSR':'special illustration rare',
    'CSR':'character super rare','CHR':'character rare',
    'HR':'hyper rare','UR':'ultra rare','AR':'art rare',
    'ACE':'ace spec rare','BWR':'gold rare',
}

def get_en_name(ko_name):
    base = re.sub(
        r'\s*(ex|EX|V|VSTAR|VMAX|GX|SAR|SSR|UR|HR|AR|SR|RR+|\[.*?\]|\(.*?\)'
        r'|붉은 달|초록|보라|파란|하얀|히스이|오리진|갈라르|팔데아)\b.*',
        '', ko_name
    ).strip()
    words = base.split()
    stripped = [w[len(pre):] for w in words for pre in KO_PREFIXES
                if w.startswith(pre) and len(w) > len(pre)]

    if '&' in base:
        parts = [p.strip() for p in base.split('&')]
        en_parts = []
        for p in parts:
            for c in [p] + p.split():
                en = KO_EN_MAP.get(c) or KO_HINT_EXTRA.get(c)
                if en:
                    en_parts.append(en)
                    break
        if en_parts:
            return ' '.join(en_parts)

    for c in [base, ko_name] + words + stripped:
        en = KO_EN_MAP.get(c) or KO_HINT_EXTRA.get(c)
        if en:
            return en
    return ''

def search_scrydex(q):
    try:
        r = requests.get(f"{SCANNER}/scrydex/search", params={'q': q, 'page': 1}, timeout=15)
        return r.json().get('results', [])
    except Exception:
        return []

def process_card(card):
    en_name = get_en_name(card['name'])
    rarity_hint = RARITY_HINT.get(card['rarity'], '')
    q_full = f"{en_name} {rarity_hint}".strip() if rarity_hint and en_name else en_name

    entry = {
        'card': card,
        'en_query': q_full,
        'suggested_jp': None,
        'suggested_en': None,
        'has_suggestion': False,
    }

    if not en_name:
        return entry

    results = search_scrydex(q_full) if q_full else []
    # fallback: 레어도 힌트 없이 이름만
    if not results and rarity_hint:
        results = search_scrydex(en_name)
        entry['en_query'] = en_name

    # 현재 카드에 이미 세팅된 쪽은 유지, 반대쪽만 찾기
    need_jp = not card.get('jp_scrydex_ref') or card['jp_scrydex_ref'].startswith('NO_')
    need_en = not card.get('en_scrydex_ref') or card['en_scrydex_ref'].startswith('NO_')

    if need_jp:
        entry['suggested_jp'] = next((r for r in results if r.get('is_jp')), None)
    if need_en:
        entry['suggested_en'] = next((r for r in results if not r.get('is_jp')), None)

    entry['has_suggestion'] = bool(entry['suggested_jp'] or entry['suggested_en'])
    return entry

def main():
    print("NO_ 카드 목록 로드 중...")
    resp = requests.get(f"{SCANNER}/scrydex/unmapped?mode=skipped", timeout=15)
    cards = resp.json().get('cards', [])
    print(f"총 {len(cards)}개 처리 시작\n")

    suggestions = []
    lock_order = {c['card_id']: i for i, c in enumerate(cards)}

    with ThreadPoolExecutor(max_workers=10) as ex:
        futures = {ex.submit(process_card, c): c for c in cards}
        done = 0
        for fut in as_completed(futures):
            done += 1
            r = fut.result()
            suggestions.append(r)
            mark = "✓" if r['has_suggestion'] else "✗"
            print(f"[{done:3d}/{len(cards)}] {mark} {r['card']['name']:<20} → {r['en_query']}")

    suggestions.sort(key=lambda x: (not x['has_suggestion'], lock_order.get(x['card']['card_id'], 0)))

    out = DATA_DIR / "auto_map_suggestions.json"
    with open(out, 'w', encoding='utf-8') as f:
        json.dump(suggestions, f, ensure_ascii=False, indent=2)

    has = sum(1 for s in suggestions if s['has_suggestion'])
    print(f"\n완료! 제안 있음: {has}개 / 없음: {len(suggestions)-has}개")
    print(f"저장: {out}")

if __name__ == '__main__':
    main()
