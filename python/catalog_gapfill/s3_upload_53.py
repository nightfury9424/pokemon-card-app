#!/usr/bin/env python3
"""53장 scrydex JP 이미지 S3 업로드 (cards/v1/jp/{card_id}.png) + CloudFront 전수검증.
기존 46배치(s3_upload_46.py)와 동일 ContentType=image/png·CacheControl. 실패시 신규key 전부 롤백.
DB·시세·visible·스캐너 변경 0. 업로드 전 SHA256/고유/덮어쓰기 가드."""
import json, hashlib, io, urllib.request, sys, time
import boto3
from PIL import Image
sys.path.insert(0, '/Users/fury/pokemon-card-app/python/catalog_import')
import import_card_set as ics

CC = 'public, max-age=31536000, immutable'   # 기존 mirror/46배치 동일
UA = "Mozilla/5.0"
PAYSHA = 'ffd3feb531b2aacf7d65b2fff3da15a01fb79d9b9d49c51bfd4a397e694da221'
s3 = boto3.client('s3', region_name='ap-northeast-2')
pay = json.load(open('final_53_payload.json'))

# 업로드 직전 가드
assert hashlib.sha256(open('final_53_payload.json','rb').read()).hexdigest()==PAYSHA, 'payload SHA256 불일치'
assert len(set(p['card_id'] for p in pay))==53, 'card_id 고유 아님'
def fetch(u): return urllib.request.urlopen(urllib.request.Request(u,headers={'User-Agent':UA}),timeout=25).read()

src_sha={}; uploaded=[]
ok_log=open('audit/s3_uploaded_53.log','w'); rb=open('audit/s3_rollback_53_keys.txt','w')
print(f"=== S3 업로드 53장 (ContentType=image/png, CacheControl='{CC}') ===")
try:
    for i,p in enumerate(pay,1):
        cid,jp=p['card_id'],p['jp_scrydex_ref']
        key=f"{ics.S3_PREFIX}/jp/{cid}.png"
        # 덮어쓰기 금지 재확인
        try: s3.head_object(Bucket=ics.S3_BUCKET,Key=key); raise RuntimeError(f'기존 key 존재 {key} — 덮어쓰기 금지')
        except s3.exceptions.ClientError as e:
            if e.response['Error']['Code']!='404': raise
        body=fetch(ics.SCRYDEX_IMG.format(ref=jp))
        if not body or len(body)<3000: raise RuntimeError(f"{jp} scrydex 이미지 비정상 {len(body) if body else 0}b")
        src_sha[cid]=hashlib.sha256(body).hexdigest()
        s3.put_object(Bucket=ics.S3_BUCKET,Key=key,Body=body,ContentType='image/png',CacheControl=CC)
        uploaded.append((cid,key,jp)); rb.write(key+"\n"); rb.flush()
        ok_log.write(f"{key}\t{src_sha[cid]}\t{p['name']}\t{jp}\n"); ok_log.flush()
        if i%10==0: print(f"  ...{i}/53 업로드")
    ok_log.close(); rb.close()
    print(f"  업로드 완료 {len(uploaded)}/53")
except Exception as e:
    print(f"\n  ❌ 업로드 중 실패: {e}\n  → 신규 업로드 {len(uploaded)}개 전부 롤백(삭제)")
    for cid,key,jp in uploaded: s3.delete_object(Bucket=ics.S3_BUCKET,Key=key)
    print("  롤백 완료. 중단."); sys.exit(1)

# 전수검증 (CloudFront)
print("\n=== 업로드 후 53장 전수검증 (CloudFront) ===")
time.sleep(2)
fails=[]; cmp_rows=[]
chk={'obj':0,'http200':0,'sha':0,'ct':0,'cc':0,'size':0,'decode':0,'dim':0}
for p in pay:
    cid,jp=p['card_id'],p['jp_scrydex_ref']
    key=f"{ics.S3_PREFIX}/jp/{cid}.png"
    try:
        ho=s3.head_object(Bucket=ics.S3_BUCKET,Key=key); chk['obj']+=1
        url=f"{ics.CDN_BASE}/jp/{cid}.png"
        r=urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':UA}),timeout=25)
        data=r.read(); http=r.status; ct=r.headers.get('Content-Type',''); cc=r.headers.get('Cache-Control','')
        cf_sha=hashlib.sha256(data).hexdigest()
        im=Image.open(io.BytesIO(data)); im.load(); w,h=im.size
        if http==200: chk['http200']+=1
        if cf_sha==src_sha[cid]: chk['sha']+=1
        if ct=='image/png': chk['ct']+=1
        if 'max-age=31536000' in cc: chk['cc']+=1
        if len(data)>0: chk['size']+=1
        chk['decode']+=1
        if w>0 and h>0: chk['dim']+=1
        cmp_rows.append(f"{cid}\t{jp}\t{src_sha[cid][:12]}\t{cf_sha[:12]}\t{'MATCH' if cf_sha==src_sha[cid] else 'DIFF'}\t{w}x{h}")
        if not(http==200 and cf_sha==src_sha[cid] and ct=='image/png' and len(data)>0 and w>0):
            fails.append((p['name'],cid,f"http={http} sha={cf_sha==src_sha[cid]} ct={ct} dim={w}x{h}"))
    except Exception as e:
        fails.append((p['name'],cid,f"err {str(e)[:40]}"))
open('audit/s3_sha_compare_53.tsv','w').write("card_id\tjp_ref\tsrc_sha\tcf_sha\tmatch\tdim\n"+"\n".join(cmp_rows))
print(f"  S3객체 {chk['obj']}/53 · CF200 {chk['http200']}/53 · SHA일치 {chk['sha']}/53 · ContentType {chk['ct']}/53")
print(f"  CacheControl {chk['cc']}/53 · size>0 {chk['size']}/53 · decode {chk['decode']}/53 · dim정상 {chk['dim']}/53")
print(f"  card_id↔jp_ref 매핑오류(SHA불일치): {53-chk['sha']}")
if fails:
    print(f"\n  ❌ 검증실패 {len(fails)} → 신규 53개 전부 롤백")
    for cid,key,jp in uploaded: s3.delete_object(Bucket=ics.S3_BUCKET,Key=key)
    for nm,cid,why in fails[:10]: print(f"    {nm} {cid}: {why}")
    print("  롤백 완료."); sys.exit(1)
print(f"\n  >>> S3 업로드 53/53 전수검증 PASS ✅ (원본 scrydex JP ↔ CloudFront SHA256 53/53 일치)")
print(f"  산출물: audit/s3_uploaded_53.log · audit/s3_rollback_53_keys.txt · audit/s3_sha_compare_53.tsv")
print(f"  ★ DB·시세·visible·스캐너 변경 0. 다음 단계는 별도 승인.")
