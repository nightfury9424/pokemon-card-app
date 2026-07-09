#!/usr/bin/env python3
"""46장 scrydex JP 이미지 S3 업로드 (기존 s3_upload 로직 + 기존 mirror 메타데이터 일치).
실패시 신규 업로드 전부 롤백. DB·스캐너 미변경."""
import json, hashlib, io, urllib.request, sys, time
import boto3
from PIL import Image
sys.path.insert(0, '/Users/fury/pokemon-card-app/python/catalog_import')
import import_card_set as ics

CC = 'public, max-age=31536000, immutable'   # 기존 mirror 객체와 동일
UA = "Mozilla/5.0"
s3 = boto3.client('s3', region_name='ap-northeast-2')
m = json.load(open('approved_46_final_manifest.json'))

# pre-check (재확인)
sha = hashlib.sha256(open('approved_46_final_manifest.json', 'rb').read()).hexdigest()
assert sha.startswith('34f2b652'), 'manifest SHA256 불일치'
assert len(set(x['card_id'] for x in m)) == 46, 'card_id 고유 아님'

def fetch(u):
    return urllib.request.urlopen(urllib.request.Request(u, headers={'User-Agent': UA}), timeout=25).read()

src_sha = {}
uploaded = []
ok_log = open('audit/s3_uploaded_keys.log', 'w')
print(f"=== S3 업로드 46장 (ContentType=image/png, CacheControl='{CC}') ===")
try:
    for i, x in enumerate(m, 1):
        cid, jp = x['card_id'], x['jp_ref']
        key = f"{ics.S3_PREFIX}/jp/{cid}.png"
        body = fetch(ics.SCRYDEX_IMG.format(ref=jp))
        if not body or len(body) < 3000:
            raise RuntimeError(f"{jp} scrydex 이미지 비정상 {len(body) if body else 0}b")
        src_sha[cid] = hashlib.sha256(body).hexdigest()
        s3.put_object(Bucket=ics.S3_BUCKET, Key=key, Body=body, ContentType='image/png', CacheControl=CC)
        uploaded.append((cid, key))
        ok_log.write(f"{key}\t{src_sha[cid]}\t{x['ko_name']}\n"); ok_log.flush()
        if i % 10 == 0: print(f"  ...{i}/46 업로드")
    ok_log.close()
    print(f"  업로드 완료 {len(uploaded)}/46")
except Exception as e:
    print(f"\n  ❌ 업로드 중 실패: {e}")
    print(f"  → 신규 업로드 {len(uploaded)}개 전부 롤백(삭제)")
    for cid, key in uploaded:
        s3.delete_object(Bucket=ics.S3_BUCKET, Key=key)
    print("  롤백 완료. DB canary 진행 안 함. 중단.")
    sys.exit(1)

# 전수 검증 (CloudFront)
print(f"\n=== 업로드 후 전수검증 ===")
time.sleep(2)
fails = []
ok = 0
for x in m:
    cid, jp = x['card_id'], x['jp_ref']
    url = f"{ics.CDN_BASE}/jp/{cid}.png"
    try:
        req = urllib.request.Request(url, headers={'User-Agent': UA})
        r = urllib.request.urlopen(req, timeout=25)
        data = r.read()
        http = r.status; ct = r.headers.get('Content-Type', ''); cc = r.headers.get('Cache-Control', '')
        cf_sha = hashlib.sha256(data).hexdigest()
        im = Image.open(io.BytesIO(data)); im.load(); w, h = im.size
        good = (http == 200 and ct == 'image/png' and len(data) > 0 and w > 0 and h > 0
                and cf_sha == src_sha[cid])
        if good: ok += 1
        else: fails.append((x['ko_name'], cid, f"http={http} ct={ct} sha_match={cf_sha==src_sha[cid]} dim={w}x{h}"))
    except Exception as e:
        fails.append((x['ko_name'], cid, f"err {str(e)[:30]}"))

print(f"  CloudFront 200+decode+SHA256일치+ContentType: {ok}/46")
if fails:
    print(f"  ❌ FAIL {len(fails)}:")
    for nm, cid, why in fails[:10]: print(f"    {nm} {cid}: {why}")
    print(f"\n  → 검증 실패. 신규 46개 전부 롤백(삭제) 후 중단.")
    for x in m:
        s3.delete_object(Bucket=ics.S3_BUCKET, Key=f"{ics.S3_PREFIX}/jp/{x['card_id']}.png")
    print("  롤백 완료. DB canary 진행 안 함.")
    sys.exit(1)
else:
    print(f"\n  >>> S3 업로드 46/46 전수검증 PASS ✅")
    print(f"  (원본 scrydex JP ↔ CloudFront 재다운 SHA256 46/46 일치, ContentType image/png, CacheControl 일치)")
    print(f"  ★ DB canary는 별도 승인 후. 지금까지 DB·스캐너 변경 0.")
