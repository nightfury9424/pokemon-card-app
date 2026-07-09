#!/usr/bin/env python3
"""
import_card_set.py — 신규 카드 세트 등록 표준 자동화 (docs/CARD_SET_IMPORT_RUNBOOK.md 로직 코드화).

JP-ref 신세트(KO 미발매)를 직접 SQL로 등록 + 시세 백필 + 이미지 업로드.
(admin POST는 JWT 필요/bash 불가, bulk-insert는 KO-code 전용이라 JP-ref엔 부적합 → 이 스크립트가 enrich 동작 복제.)

★모든 write 기본 --dry-run (BEGIN→검증→ROLLBACK). 실반영은 --apply 명시해야 함.

사용:
  # dry-run (전체 검증, 실반영 0)
  python3 import_card_set.py --input m5_ja_final_payload.csv --product-id PRD_xxx
  # canary 2장만 실반영(숨김 등록+백필+이미지)
  python3 import_card_set.py --input m5_ja_final_payload.csv --product-id PRD_xxx --canary m5_ja-46,m5_ja-114 --apply
  # 전체 실반영
  python3 import_card_set.py --input m5_ja_final_payload.csv --product-id PRD_xxx --apply
  # 등록·검증 끝난 카드 공개
  python3 import_card_set.py --input ... --product-id ... --canary m5_ja-46 --make-visible

입력 CSV/JSON 컬럼(유연): jp_scrydex_ref(필수), ko_name|name(필수), rarity_code|rarity(필수),
  collection_number(필수), super_type(기본 POKEMON), sub_type(없으면 scrydex stage 자동),
  official_card_code(기본 NULL), en_scrydex_ref(기본 NO_EN).
"""
import argparse, csv, json, os, re, sys, subprocess, hashlib, random, secrets, urllib.request

# ── 환경 (RUNBOOK §0,3) ──
PEM   = os.path.expanduser("~/pem/LightsailDefaultKey-ap-northeast-2.pem")
SSH   = f"ubuntu@52.78.3.120"
PGEXEC= "docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db"
S3_BUCKET = "pokefolio-beta-assets-759135635310-ap-northeast-2-an"
S3_PREFIX = "cards/v1"
CDN_BASE  = "https://d3shjhylvfe40j.cloudfront.net/cards/v1"
SCRYDEX_IMG = "https://images.scrydex.com/pokemon/{ref}/medium"
SCRYDEX_CARD= "https://scrydex.com/pokemon/cards/_/{ref}"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
# v6 NORMAL tier 계수 (RUNBOOK §4). ★MUR은 예외: v6_apply가 SEED무관 HIT_TOP 강제 →
#   KO=jp_grail×hrr('MUR')=jp×0.641648 (RRH['MUR']0.441648+0.2). NORMAL 0.30 아님.
FROZEN_RTR = {'RR':0.387712,'AR':0.27933,'SR':0.442282,'SAR':0.299559,'MA':0.354445,
              'RRR':0.579566,'UR':0.831831,'HR':0.322597,'SSR':0.579979,
              'MUR':0.641648}  # HIT_TOP (hrr), NORMAL 아님

def sh(cmd):
    return subprocess.run(cmd, shell=True, capture_output=True, text=True)

def run_sql(sql):
    """prod psql에 SQL 파이프 (ssh+docker)."""
    p = subprocess.run(f'ssh -i "{PEM}" -o ConnectTimeout=12 -o StrictHostKeyChecking=no {SSH} "{PGEXEC}"',
                       input=sql, shell=True, capture_output=True, text=True)
    return p.stdout + p.stderr

def get(url, binary=False):
    r = urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=25)
    return r.read() if binary else r.read().decode('utf-8', 'ignore')

# ── scrydex (RUNBOOK §2 sub_type, §4 history) ──
def scrydex_history(ref):
    """_Raw_ Chartkick 차트 → [(date, usd)]. ScrydexLiveClient 동일 파싱."""
    d = get(SCRYDEX_CARD.format(ref=ref))
    m = re.search(r'_Raw_[^"]*",\s*(\[.*?\]),\s*\{', d)
    da = re.search(r'"data":\s*(\[\[.*?\]\])', m.group(1), re.S) if m else None
    if not da: return []
    return [(dt, float(v)) for dt, v in re.findall(r'\["(\d{4}-\d{2}-\d{2})",\s*(null|\d+\.?\d*)\]', da.group(1)) if v != 'null' and float(v) > 0]

def scrydex_subtype(ref):
    """카드 stage → STAGE2/STAGE1/BASIC."""
    d = get(SCRYDEX_CARD.format(ref=ref))
    m = re.search(r'>(Basic|Stage 1|Stage 2)<', d)
    return m.group(1).upper().replace(' ', '') if m else None

def live_rate():
    """exchange_rate_usd.price / 100.0 (RUNBOOK §4 ★)."""
    out = run_sql("\\pset tuples_only on\nSELECT price FROM price_snapshots WHERE card_id='exchange_rate_usd' ORDER BY traded_at DESC LIMIT 1;")
    m = re.search(r'(\d+)', out)
    return int(m.group(1)) / 100.0 if m else 1530.0

def psid(): return hashlib.md5(secrets.token_bytes(16)).hexdigest()
def cardid(): return "CRD_" + secrets.token_hex(10).upper()
def q(s): return "NULL" if s is None else "'" + str(s).replace("'", "''") + "'"

# ── payload ──
def load_payload(path):
    rows = []
    if path.endswith('.json'):
        data = json.load(open(path))
    else:
        data = list(csv.DictReader(open(path)))
    def pick(r, *keys):
        for k in keys:
            v = r.get(k)
            if v not in (None, ''): return v
        return None
    for r in data:
        jp = pick(r, 'jp_scrydex_ref', 'jpScrydexRef', 'jp_ref')
        if not jp: continue
        rows.append(dict(
            jp_ref=jp,
            name=pick(r, 'ko_name', 'name'),
            rarity=(pick(r, 'rarity_code', 'rarityCode', 'rarity') or '').upper(),
            col=pick(r, 'collection_number', 'collectionNumber', 'number'),
            super_type=pick(r, 'super_type', 'superType') or 'POKEMON',
            sub_type=pick(r, 'sub_type', 'subType'),
            official=pick(r, 'official_card_code', 'officialCardCode'),
            en=pick(r, 'en_scrydex_ref', 'enScrydexRef') or 'NO_EN',
            card_id=pick(r, 'card_id', 'cardId'),   # ★있으면 그대로 사용(선생성), 없으면 cardid()로 생성
        ))
    return rows

def validate(rows, product_id):
    errs = []
    jps = [r['jp_ref'] for r in rows]
    # 입력 중복
    dup = {x for x in jps if jps.count(x) > 1}
    if dup: errs.append(f"입력 jp_ref 중복: {dup}")
    # prod 기존 존재(멱등)
    inlist = ",".join("'%s'" % j for j in jps)
    out = run_sql(f"\\pset tuples_only on\nSELECT jp_scrydex_ref FROM cards WHERE jp_scrydex_ref IN ({inlist});")
    existing = set(re.findall(r'm\d+_ja-\d+|[a-z0-9]+_ja-\d+', out))
    for r in rows:
        if not (r['name'] and r['rarity'] and r['col']): errs.append(f"{r['jp_ref']}: name/rarity/col 누락")
        if r['rarity'] not in FROZEN_RTR: errs.append(f"{r['jp_ref']}: 미지원 rarity {r['rarity']}")
    return errs, existing

# ── SQL 생성 ──
def card_values(r, product_id, card_id):
    sub = r['sub_type'] or scrydex_subtype(r['jp_ref'])
    return (f"({q(card_id)},{q(product_id)},{q(r['official'])},{q(r['name'])},{q(r['col'])},NULL,"
            f"{q(r['rarity'])},'KO',{q(r['super_type'])},{q(sub)},{q(r['en'])},{q(r['jp_ref'])},false)")

def backfill_values(card_id, jp_ref, rarity, rate):
    ratio = FROZEN_RTR[rarity]
    jpv, kov = [], []
    for dt, usd in scrydex_history(jp_ref):
        jpk = round(usd * rate); ko = round(jpk * ratio); cp = round(ko * (1 + (random.random()*0.03 - 0.015)))
        jpv.append(f"('{psid()}',{q(card_id)},'SCRYDEX_JP',{jpk},'RAW','{dt} 12:00:00','{dt} 12:00:00',now(),{usd},'USD')")
        kov.append(f"('{psid()}',{q(card_id)},'KO_ESTIMATED',{ko},{cp},'RAW','{dt} 12:00:00','{dt} 12:00:00',now())")
    return jpv, kov

def build_sql(targets, product_id, rate, commit):
    """targets=[(row, card_id)]. commit=False면 BEGIN..ROLLBACK, True면 BEGIN..COMMIT."""
    cv = [card_values(r, product_id, cid) for r, cid in targets]
    jpv, kov = [], []
    for r, cid in targets:
        a, b = backfill_values(cid, r['jp_ref'], r['rarity'], rate); jpv += a; kov += b
    ids = ",".join(q(cid) for _, cid in targets)
    s = ["\\set ON_ERROR_STOP on",
         "\\echo '=== BEFORE 체크섬(신규제외 동일해야) ==='",
         "SELECT count(*) tot, sum(price) sm FROM price_snapshots;",
         "BEGIN;",
         "INSERT INTO cards (card_id,product_id,official_card_code,name,collection_number,card_number,rarity_code,language,super_type,sub_type,en_scrydex_ref,jp_scrydex_ref,is_visible) VALUES",
         ",\n".join(cv) + ";"]
    if jpv:
        s += ["INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,card_status,traded_at,collected_at,created_at,raw_price,raw_currency) VALUES", ",\n".join(jpv) + ";"]
    if kov:
        s += ["INSERT INTO price_snapshots (price_snapshot_id,card_id,source,price,chart_price,card_status,traded_at,collected_at,created_at) VALUES", ",\n".join(kov) + ";"]
    s += ["COMMIT;" if commit else "ROLLBACK;",
          "\\echo '=== 신규 확인 ==='",
          f"SELECT jp_scrydex_ref ref,rarity_code rar,is_visible vis,sub_type,"
          f"(SELECT count(*) FROM price_snapshots p WHERE p.card_id=c.card_id AND source='SCRYDEX_JP') jp_n,"
          f"(SELECT count(*) FROM price_snapshots p WHERE p.card_id=c.card_id AND source='KO_ESTIMATED') ko_n "
          f"FROM cards c WHERE c.card_id IN ({ids}) ORDER BY rar;",
          "\\echo '=== 기존 무손상(신규제외 체크섬, BEFORE와 동일해야) ==='",
          f"SELECT count(*) tot, sum(price) sm FROM price_snapshots WHERE card_id NOT IN ({ids});"]
    return "\n".join(s), [(r, cid) for r, cid in targets]

# ── S3 이미지 (RUNBOOK §3) ──
def s3_upload(card_id, jp_ref, apply):
    key = f"{S3_PREFIX}/jp/{card_id}.png"
    if not apply:
        return f"[DRY] would upload {SCRYDEX_IMG.format(ref=jp_ref)} → s3://{S3_BUCKET}/{key}"
    import boto3
    body = get(SCRYDEX_IMG.format(ref=jp_ref), binary=True)
    boto3.client("s3", region_name="ap-northeast-2").put_object(Bucket=S3_BUCKET, Key=key, Body=body, ContentType="image/png")
    code = sh(f'curl -s -o /dev/null -w "%{{http_code}}" "{CDN_BASE}/jp/{card_id}.png"').stdout
    return f"uploaded {key} · CloudFront HTTP {code}"

def rollback_sql(card_ids, product_id):
    ids = ",".join(q(c) for c in card_ids)
    return (f"DELETE FROM price_snapshots WHERE card_id IN ({ids});\n"
            f"DELETE FROM cards WHERE card_id IN ({ids});\n"
            f"-- S3: for cid: aws s3 rm s3://{S3_BUCKET}/{S3_PREFIX}/jp/<cid>.png\n"
            f"DELETE FROM products WHERE product_id={q(product_id)} AND NOT EXISTS (SELECT 1 FROM cards WHERE product_id={q(product_id)});")

# ── main ──
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', required=True)
    ap.add_argument('--product-id', required=True)
    ap.add_argument('--canary', help='jp_ref 콤마구분 (이것만 처리)')
    ap.add_argument('--apply', action='store_true', help='실반영(없으면 dry-run)')
    ap.add_argument('--make-visible', action='store_true', help='등록완료 카드 is_visible=true')
    ap.add_argument('--skip-images', action='store_true', help='S3 이미지 업로드 스킵(이미지 별도 선업로드 시)')
    args = ap.parse_args()
    random.seed(46)

    rows = load_payload(args.input)
    if args.canary:
        sel = set(args.canary.split(','))
        rows = [r for r in rows if r['jp_ref'] in sel]
    print(f"대상 {len(rows)}장 · product {args.product_id} · {'APPLY' if args.apply else 'DRY-RUN'}")

    if args.make_visible:
        ids = run_sql(f"\\pset tuples_only on\nSELECT card_id FROM cards WHERE jp_scrydex_ref IN ({','.join(q(r['jp_ref']) for r in rows)});")
        cids = re.findall(r'CRD_[0-9A-F]+', ids)
        sql = f"UPDATE cards SET is_visible=true WHERE card_id IN ({','.join(q(c) for c in cids)});\nSELECT card_id,is_visible FROM cards WHERE card_id IN ({','.join(q(c) for c in cids)});"
        print(run_sql(sql) if args.apply else "[DRY] " + sql)
        return

    errs, existing = validate(rows, args.product_id)
    if existing: print(f"⚠ 이미 prod 존재(멱등 skip): {existing}")
    rows = [r for r in rows if r['jp_ref'] not in existing]
    if errs: print("검증오류:\n  " + "\n  ".join(errs)); sys.exit(1)
    if not rows: print("처리할 신규 카드 없음(전부 존재)"); return

    rate = live_rate(); print(f"환율 {rate} (exchange_rate/100)")
    targets = [(r, r.get('card_id') or cardid()) for r in rows]   # ★manifest card_id 우선(선생성), 없으면 생성
    sql, _ = build_sql(targets, args.product_id, rate, commit=args.apply)
    print("=== SQL 실행 ===")
    print(run_sql(sql))
    if args.skip_images:
        print("=== 이미지: --skip-images (별도 선업로드) ===")
    else:
        print("=== 이미지 ===")
        for r, cid in targets:
            print("  " + s3_upload(cid, r['jp_ref'], args.apply))
    print("=== 롤백 SQL (필요시) ===")
    print(rollback_sql([cid for _, cid in targets], args.product_id))
    if not args.apply:
        print("\n※ DRY-RUN: 실반영 0 (cards/price_snapshots ROLLBACK, S3 미업로드). 실행은 --apply.")
    else:
        print("\n✓ APPLY 완료. 검증 후 --make-visible 로 공개.")

if __name__ == '__main__':
    main()
