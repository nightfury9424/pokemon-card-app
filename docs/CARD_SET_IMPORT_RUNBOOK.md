# 신규 카드 세트 등록 런북 (CARD_SET_IMPORT_RUNBOOK)

> 2026-06-21 어비스아이(m5_ja) canary에서 검증한 표준 절차. 다음 신규 세트는 **payload 준비 → canary → 전체** 로 끝낸다.
> 자동화 스크립트: `python/catalog_import/import_card_set.py` (이 문서의 로직을 코드화). 모든 write 기본 `--dry-run`, `--apply` 명시해야 실반영.

## 0. 왜 직접 SQL인가 (기존 경로 한계)
- `POST /api/admin/cards`(단건) = **풀 파이프라인**(cards INSERT + enrich: 14일 SCRYDEX_JP 백필 + KO_ESTIMATED + S3 이미지 미러). **단 admin JWT(구글 OAuth) 필요 → bash 불가.**
- `POST /api/admin/cards/bulk-insert` = **KO 전용**(officialCardCode/name/rarity/collectionNumber만, **jp_ref·enrich·이미지 없음**). JP-ref 신세트(m5_ja류)엔 부적합.
- → JP-ref 신세트는 **직접 SQL로 enrich 동작을 복제** (이 런북). prod DB 접근: `ssh -i ~/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120` → `docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db`.

## 1. product 생성 (세트당 1회)
```sql
INSERT INTO products (product_id,name,series_name,product_type,language,created_at,updated_at)
VALUES ('PRD_<21hex대문자>','MEGA 확장팩 「세트명」','MEGA','BOOSTER','KO',now(),now());
```
- product NOT NULL: product_id·name·language·created_at·updated_at. FK 없음.
- 예(어비스아이): `PRD_1B9CC7C6D61653EEDEB28` = `MEGA 확장팩 「어비스아이」`.

## 2. cards 필드 + 기본값
- **card_id = `CRD_` + 20 HEX 대문자** (예 `CRD_FA4BBF0978E1CA423377`). IdGenerator 관례.
- NOT NULL: card_id·product_id·name·language·super_type. FK **없음**.
- 표준값(신세트 chase): `language='KO'`·`super_type='POKEMON'`·`official_card_code=NULL`(KO 미발매)·`card_number=NULL`·`image_url=NULL`·`local_image_path=NULL`·`is_promo_exclusive=false`·`name_locked=false`·`popularity_score=0`·**`is_visible=false`로 시작**(완성 후 true).
- **`en_scrydex_ref='NO_EN'`** (NULL 아님 — 기존 chase 카드 형식. `price_scrydex.py`가 `NOT LIKE 'NO_%'`로 제외 처리하므로 NO_EN=EN없음).
- **sub_type = scrydex stage 기준**: 메가 ex라도 종족 진화단계 따름. 메가개굴닌자=`STAGE2`(개굴닌자 2진화), 메가다크라이=`BASIC`(다크라이 기본). scrydex 카드페이지 stage 토큰(`Basic`/`Stage 1`/`Stage 2`) → 대문자·공백제거(`BASIC`/`STAGE1`/`STAGE2`).
- 템플릿 row = 기존 닌자스피너 chase (m4_ja-114 SAR, 2026-05-30 admin 추가분).

## 3. 이미지 (CloudFront, image_url 컬럼은 NULL)
- **S3 key**: `cards/v1/jp/{card_id}.png` · 버킷 `pokefolio-beta-assets-759135635310-ap-northeast-2-an` (region ap-northeast-2).
- **CloudFront**: `https://d3shjhylvfe40j.cloudfront.net/cards/v1/jp/{card_id}.png` (= prod env `CARD_CDN_BASE`).
- **DB `image_url`/`local_image_path` = NULL**. 앱이 card_id로 URL 조립: `CardCdnUrls.forCard`/Flutter `resolveCardImageUrl` = `{CARD_CDN_BASE}/jp/{card_id}.png` (jp_ref valid 시). scrydex CDN fallback **아님**(CLAUDE.md stale) → **S3 업로드 필수**, 안 하면 카드뒷면.
- 업로드: `mirror_card_images_to_s3.py`/`mirror_ninja_spinner_images.py` 패턴(boto3, `~/.aws`). source = scrydex `images.scrydex.com/pokemon/{jp_ref}/medium`.
- 업로드 후 **CloudFront HTTP 200** 확인.

## 4. 시세 백필 (날짜당 price_snapshots 2행)
- 소스 = scrydex 카드페이지 `_Raw_` Chartkick 차트(날짜별 USD raw). 백엔드 `ScrydexLiveClient`와 동일 파싱.
- **★환율: `exchange_rate_usd.price`는 ×100 정수저장 → 실환율 = `price/100.0`** (ExchangeRateClient:90). ★2026-06-21 이거 100배 오류를 dry-run이 잡음. 굵게.
- 백필 환율 정책 = **실행시점 환율 1개를 과거 14일 전체에 일괄** (backfillKoEstimatedHistory `getUsdToKrw()` 루프밖 1회 + 닌자스피너 실데이터 price/raw_price 일정 확인).
- **SCRYDEX_JP row**: price=KRW(usd×rate), raw_price=USD, raw_currency='USD', card_status='RAW', chart_price=NULL, traded_at=실제날짜.
- **KO_ESTIMATED row**: price=v6값, raw_price=NULL, **chart_price=±1.5% 적용값(별도 row 아니라 이 row의 컬럼)**, card_status='RAW', traded_at=실제날짜.
- **v6 KO = JP raw(KRW) × FROZEN_RTR[`rarity|NORMAL`]** (신세트=NORMAL tier, SEED 미등록): RR 0.387712·AR 0.27933·SR 0.442282·SAR 0.299559·MA 0.354445. (진짜 chase는 추후 SEED 큐레이션으로 HIT 승격.)
- **chart_price = round(KO × (1 + (random×0.03−0.015)))** = `ko_chart_price_daily.sh` 공식(±1.5% 균등난수).
- price_snapshot_id = 32 hex (VARCHAR 길이제한 ~46, 프리픽스 금지). 롤백은 card_id 기준.

## 5. 자동 정기 동기화 포함 조건
신규카드가 **`language='KO'` + 유효 `jp_scrydex_ref`** 면 다음 전부 자동 포함:
- **21:00 `price_scrydex.py`**(back컨테이너 `/app/python/`): `WHERE language='KO' AND jp_scrydex_ref NOT LIKE 'NO_%'` → SCRYDEX_JP raw 매일 fetch
- **23:45 refreshKo**(Java): `findAllLatestScrydexJp()` 전수 → KO_ESTIMATED
- **23:52 `v6_apply.py`**: `WHERE language='KO'` → full v6 보정
- **23:57 `ko_chart_price_daily.sh`**: 당일 KO_ESTIMATED → chart_price ±1.5%
→ **백필 = 과거 1회, 이후는 자동.**

## 6. 배포 순서
1. product 확인/생성 · 2. metadata 검증(중복/스키마) · 3. canary 2장 dry-run(BEGIN→검증→ROLLBACK) · 4. **canary 숨김(is_visible=false) 등록 + 백필 COMMIT** · 5. S3 이미지 업로드 · 6. CloudFront 200 · 7. 앱 상세 API/차트 확인 · 8. **기존 무손상**(신규제외 count+sum 체크섬 전후 동일) · 9. **is_visible=true** · 10. 나머지 세트 동일 처리 · 11. scanner card_meta/FAISS 재빌드(별도) · 12. 다음 정기 sync 확인.

## 7. 롤백
```sql
DELETE FROM price_snapshots WHERE card_id IN (<canary card_ids>);
DELETE FROM cards WHERE card_id IN (<canary card_ids>);
-- product는 다른 카드 연결됐으면 삭제 금지
DELETE FROM products WHERE product_id='<PID>' AND NOT EXISTS (SELECT 1 FROM cards WHERE product_id='<PID>');
```
S3: `aws s3 rm s3://pokefolio-beta-assets-.../cards/v1/jp/{card_id}.png` (card_id별 2개).

## 8. scanner 재빌드 (별도, 카드 등록 ≠ 스캔)
- 절차: ①prod→로컬DB 신규카드 sync(build_db.py가 로컬 `WHERE language='KO'` 조회) ②이미지 `m5_ja_images/{jp_ref}.png`→`scanner/data/cards/{card_id}_jp.png` 복사 ③`db/build_db.py` **전체 재빌드**(로컬DB 카드만 인덱싱→orphan 자동정리) ④스캐너 재시작.
- ★**augment = 단일이미지(jp만, KO미발매 신세트)면 10뷰**(`augment10`: 원본+밝기4+회전4+크롭1)=**기본 10벡터 보장**. jp+en 2장이면 augment(5뷰)×2=10, jp+en+ko=15. **신세트는 EN/KO 이미지 없어 jp 1장뿐→augment10 필수**(안 그러면 5벡터). build_db.py+build_missing.py 둘 다 반영(2026-06-21).
- ★card_id별 vector_count 기준(전체/평균 아님). 10미만=이미지부족 or augment 미적용.
- 실행: `cd scanner && KMP_DUPLICATE_LIB_OK=TRUE OMP_NUM_THREADS=1 MKL_NUM_THREADS=1 OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES /Users/fury/miniconda3/envs/scanner_v2/bin/python db/build_db.py`. 백업 `.bak_pre_*` 먼저. ~3800장 ≈ 23분(mps).
- 증분(신규 N장만, 기존 무손상·빠름)=`db/build_missing.py`(`/tmp/missing_cards.json`=[{cardId,name,rarity,officialCode,jpRef,enRef}], base=현 card_db.faiss에 append). 39장 ≈ 1분.

## 9. ★★ 스캐너 prod 배포 (모델 일치 필수 — 안 그러면 prod 스캔 전체 깨짐)
- 앱 스캔 = **prod `pokefolio-scanner` 컨테이너**(8080 back→localhost:8082). 인덱스 = 호스트 마운트 `/opt/pokefolio/data/faiss`(→컨테이너 `/app/scanner/db`). 모델 = `/opt/pokefolio/data/models/dinov2_finetuned`.
- ★★**인덱스는 그걸 빌드한 모델과 1:1 짝.** FAISS 벡터(빌드 모델)와 쿼리 임베딩(prod 모델)이 다르면 **전체 오매칭**(score~0.1). ★**prod 모델 md5 `3368c0dfea2072bd60a8aad8bd0b2c63`(2026-05-04). 로컬 `scanner/model/dinov2_finetuned`이 이거랑 같은지 빌드 전 md5 확인.** (2026-06-21 로컬 모델이 divergent 27536…이라 첫 배포가 prod 스캔 깸→롤백→prod모델 받아 재빌드. 로컬 모델을 prod모델로 교정함.)
- 배포 절차: ①prod 모델 md5와 로컬 모델 일치 확인(틀리면 prod모델 scp받아 로컬 교체 후 빌드) ②`build_missing.py`/`build_db.py`로 인덱스 빌드 ③**로컬 스캐너 재시작+identify 검증(기존+신규 둘 다 score>0.9)** ④prod 백업(`sudo cp …faiss …bak`) ⑤scp 인덱스→prod`/tmp`→`sudo cp`→`/opt/pokefolio/data/faiss`+chmod644 ⑥`docker restart pokefolio-scanner` ⑦prod identify 검증(기존+신규). **롤백=백업 cp 복원+restart.**

## 9. 검증 산출물 (스크립트가 생성)
- `prod_local_card_diff` / 백필 dry-run row count / before-after 체크섬 / rollback SQL / 실행보고서.

## ★ MUR 예외 (반드시 주의)
- **MUR은 NORMAL 계수 아님.** v6_apply가 SEED 무관 **HIT_TOP 강제**(line 123) → `KO=jp_grail×hrr('MUR')=jp×0.641648`(RRH['MUR']0.441648+0.2). NORMAL 0.30 쓰면 절반으로 잘못 들어감. import_card_set.py FROZEN_RTR에 `'MUR':0.641648` 박음.
- ★**갭스캔 시 MUR 빠지기 쉬움**: 어비스아이 MUR=118/081(SAR 117 *뒤* 골드 grail). base+SAR범위 너머 마지막 번호 = MUR. 세트마다 확인. (어비스아이 45고레어=MUR1+SAR6+SR18+AR12+RR8, 도구6 제외 39 등록.)
- 힛카드(마케팅) = MUR1+SAR6 = 7종. (v6 가격은 MUR만 HIT_TOP, SAR는 NORMAL=보수적. 원하면 SAR도 SEED 큐레이션으로 HIT 승격.)

## ★ 어비스아이(m5_ja) 실행 완료 (2026-06-21)
- product `PRD_1B9CC7C6D61653EEDEB28`. **39장 등록**(MUR 포함, 도구 6 제외). 총 카드 3755→**3794**.
- canary 2장(46 RR·114 SAR) → 검증(앱 차트·이미지·시세 실확인) → 37장 `import_card_set.py --apply`.
- 백필: SCRYDEX_JP 538 + KO_ESTIMATED 538(chart_price). 환율 1530.44. **MUR KO=491,002원**(HIT_TOP)·SAR 208,992(NORMAL).
- 이미지 39/39 CloudFront 200. **기존 1,255,992행/224,633,323,468 완전 무변경**(전 과정).
- ★발견 오류 2개(dry-run이 잡음): ①exchange_rate ×100 ②MUR이 HIT_TOP인데 NORMAL로 갈 뻔.
- 잔여: scanner card_meta/FAISS **전체 재빌드**(3794 기준, 471 stale orphan 정리 포함).
