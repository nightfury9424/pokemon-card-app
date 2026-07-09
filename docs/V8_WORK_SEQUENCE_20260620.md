# v8 KO 카탈로그 + 시세 작업 서순 (2026-06-20 확정) — 다음 세션 진입점

> 사용자 확정 서순. 순서대로 진행. 합치는 건 4단계뿐.

## ━━ 전체 서순 (4단계, 순서대로) ━━

### 1. 카탈로그 갭필 — pokemoncard에서 누락 고레어(RR+) 싹 긁기 ★먼저
- **대상**: 우리 DB의 각 KO 시리즈(세트, `official_card_code` prefix 단위 예 `BS2026003`)
- **방법**: 시리즈마다 **빈 여백(누락 번호) + 앞뒤 ±100** 범위 스캔 → pokemoncard.co.kr에서 우리가 없는 카드 찾기
  - 예: 닌자스피너 base /083인데 SR/SAR/MUR은 090·104·120 등 **base 밖 번호** → 그래서 max+100까지, min-100까지 확장 스캔 필수
- **필터**: **RR 이상 고레어만** (RR/SR/SAR/AR/HR/UR/MUR/SSR/CHR/CSR). 커먼/언커먼 제외
- **이유**: 닌자스피너(BS2026003)처럼 **chase(SR/SAR/AR/MUR)가 통째로 누락**된 세트 다수. 현재 DB엔 RR 8장만, chase 0
- **산출**: 누락 고레어 → 카탈로그 추가 (name/rarity/collection_number/image/official_card_code/jp·en ref)
- **도구**: `python/catalog_gapfill/` (기존: ko_master_build·gaps_enriched·final_add_payload 등), pokemoncard 크롤. 추가경로=`POST /api/admin/cards` 단건(bulk 금지=ref NULL)
- **검증 사례**: 메가개굴닌자 ex SR(닌자스피너) = DB없음·add리스트없음·KO마스터크롤없음 = 미소싱 갭

### 2. 당근 데이터 매핑
- 당근 크롤분(**432건 신규** + 기존 검수대기) → `price_review.html`(스캐너 8082)로 카드 매핑
- 1번 끝나야 닌자스피너 SR 등 chase 매핑 가능
- 도구: **수동매핑 버튼(이름+DINOv2 하이브리드, 2026-06-20 추가됨)** + 후보 + 단일/버림
- (선택) "카탈로그 없음" 보류 버튼 = 1번이 대부분 해결하면 잔여용으로만

### 3. 스니덩(SNKRDUNK) 매핑
- SNKRDUNK catalog **41,610건**(백업 `~/pokefolio_backups/snkrdunk_catalog_20260620/`) → 스캐너 이미지매칭으로 우리 카드에 매핑
- priority(14,089) 우선 · MATCH_HIGH만(score≥0.75 + 세트/번호/레어도 크로스체크)
- 도구: `python/price_v8/snkrdunk_collect.py --match-and-collect --catalog-csv ...priority.csv`

### 4. 시세 수집 (마지막)
- 매핑 완료 카드들 시세 일괄 수집
- **KO** = 당근 체결가(한글판 RAW 단품), **JP** = SNKRDUNK SOLD(A/PSA9/PSA10, 최근 60일)
- v8 모델로 합침: ①KO체결 ②SNKRDUNK A급×계수 ③Scrydex fallback. 교차밴드 ±25%

## ━━ 현재 상태 (2026-06-20) ━━
- **당근**: 432건 크롤 완료(거래완료 배지 버그 fix) · classify 완료(후보 채워짐) · 리뷰 도구 작동(수동매핑+디노 버튼 추가)
- **SNKRDUNK**: catalog 41,610 수집·백업 완료 · 매핑 대기
- **카탈로그 갭**: 닌자스피너 chase 통째 누락 등 다수 → **1번 작업이 시작점**
- **NAVER**: v8 미사용 확정(일판/등급/경매 오염)
- **리뷰 도구 변경**: scanner/main.py 새 엔드포인트 `/admin/review/{id}/search`(이름+디노 재랭킹) + price_review.html Pass1 🔍수동 버튼. 스캐너 재시작 완료

## ━━ 1번 진행상황 (2026-06-20 밤, 메소드 검증 완료) ━━

### ✅ 검증된 크롤 메소드 — 도구 `python/catalog_gapfill/pokemoncard_gap_scan.py`
- pokemoncard.co.kr `/cards/detail/{CODE}` = **서버사이드 렌더**(SPA 아님). 실측 확인.
- **존재 판별** = 본문 길이(len>15000=존재 / ~11356=빈템플릿). **레어도** = `<span id="no_wrap_by_admin">RR</span>` 텍스트
  (★742-base 대형세트 시크릿은 레어도가 아이콘이라 '?' → base 초과 번호+이름(ex)로 chase 판정). **번호** `NNN/MMM`(MMM=base크기).
- 도구 사용: `--sets BS2026002` / `--discover 2026`(코드발견) / `--all-held`(보유 전세트 대량). 출력 `pokemoncard_gap_missing.csv`. write 0.

### ★ 갭 모델 정정 (실측으로 전제 수정)
- "base 위 ±N 스캔" **맞다** — BS2026002(base80)는 081~105에 AR/SR chase 실재. 사용자 모델 검증됨.
- 단 **세트마다 다름**: BS2026003(base83)은 base 위 chase 0(이 세트만 chase 없음). → 세트당 **full 스캔(001..종료)** 이 정답. ±100은 안전 윈도우.
- ★**우리가 0장 보유한 세트코드는 ±100으로 못 찾음** → `--discover`로 **세트코드 공간**(BS2024xxx~2026xxx) 별도 발견 필요.

### 첫 산출 (2026 MEGA 신세트 대조 — 커버리지 ~95%, 큰 누락 없음)
- **BS2026001**(대형 base742): 시크릿 743~766 거의 보유. **누락=759 메가다부니 ex**(+767/768 기본에너지 2).
- **BS2026002**(base80): chase ex(093~100 SR 메가아쿠스타/픽시/지가르데/무장조·나옹 ex 등) **전부 보유**.
  **누락 7=061 나옹 ex(RR)·101~104·109·110 SR(트레이너/스타디움)**. → `pokemoncard_gap_missing.csv`.
- BS2026003=83장 완비(chase 없음). ★주의: 세션1의 "BS2026003=닌자스피너" 라벨은 오인(003=독침붕 ex).

### 다음 실행 (미완 — 정직히 미실행)
1. `--discover 2026`/`2025`/`2024`로 **세트코드 전수 발견** → 보유 0장 세트(=숨은 chase) 탐지.
2. `--all-held` 전 세트 full 스캔(주의: BS2026001만 ~770req, 정중 딜레이로 대량 → 의도적 실행/체크포인트).
3. 누락 리스트 → 기존 jp/en ref 매칭 파이프(`jp_match.py`·`en_match2.py`) → `admin_payload.py` → **`POST /api/admin/cards` 단건**(승인후). ★ref 매칭·mass POST 전 Codex 리뷰.

## ━━ 2026-06-20 밤 실행결과 (scrydex 갭툴 + 스캐너 진단) ━━

### ★ scrydex JP 전수 갭 = KO 미발매 신세트의 유일·최속 소스 (검증완료)
- 도구 `python/catalog_gapfill/scrydex_set_gap.py`. 세트페이지 1요청=전체 카드 ref+EN slug+이미지+레어도. pokemoncard보다 압도적.
- JP MEGA 신세트 3개 결과 (산출 `scrydex_set_gap_missing.csv`, 60행):
  | 세트 | slug | 보유 | 누락 고레어 |
  |---|---|---|---|
  | m3_ja 니힐제로 | nihil-zero | 38 | 7 (나옹 ex RR + 트레이너 SR 6) |
  | m4_ja 닌자스피너 | ninja-spinner | 36 | 9 (노라키 AR + 트레이너 SR 8) |
  | **m5_ja 어비스아이** | abyss-eye | **0** | **44** ★세트통째: 메가다크라이/제라오라/샹델라/몰드류 ex 등 RR·SR·SAR |
- ★**m5_ja(어비스아이)=진짜 큰 갭**. KO·EN 미발매라 pokemoncard 불가. 추가 시 KO명 필요(미발매=번역/큐레이션), jp ref(보유)·이미지·번호·레어도는 scrydex에서 확정.

### ★ 스캐너 "안 뜸" 근본원인 = 로컬 dev DB가 prod보다 stale (FAISS 아님)
- 스캐너 검색 `/admin/cards/search`·후보 enrich = `localhost/pokemon_card_db/nightfury` **로컬 dev DB** 조회(main.py:410 _DB_CFG).
- 로컬 m4_ja **9** vs prod **36** → 메가개굴닌자 SR 098·SAR 114가 로컬에 없어 검색·후보에 안 뜸. (FAISS엔 11벡터씩 정상 인덱스됨, 앱=prod는 4종 다 노출)
- **보완A = 로컬 dev DB ← prod 동기화** (당근/스니덩 매핑 작업 전 필수, 안 하면 리뷰툴 추천이 prod와 어긋남). 방법 미결정(전체 prod dump→restore vs snapshot upsert).

### pokemoncard KO 트랙 — discover 결과 + 주의
- `pokemoncard_gap_scan.py --discover 2024/2025/2026` 실행. 세트코드 공간·세트별 보유 스코핑 완료.
- ★**"보유 0장" 신뢰불가**: blank official_card_code + cross-set 아티팩트(뮤ex BS2025002=코드0이나 다른세트로 다수보유). KO 트랙 풀크롤 전 **JP-ref 디둡 선행 필수**(안 하면 거짓 누락 양산).
- ★도구 한계: `--all-held`/full스캔 maxn 기본 130 → base>130 대형세트(BS2026001=742·2024018=175·2025015=193) 시크릿범위 못 닿음. maxn=base+30 동적조정 필요.

## 진행완료 (2026-06-20 밤)
1. ✅ **로컬 dev DB ← prod 동기화 38장** 완료·검증. prod-only 38(메가개굴닌자 SR098·SAR114 + m4_ja 27 등)을 로컬 cards에 INSERT(staging+ON CONFLICT, is_visible=true). m4_ja 9→36. **스캐너 검색 "메가개굴닌자"=4건(022·098·114·120) 정상** → 원래 "SR 안 뜸" 해결. (FK없음·NOT NULL 전부 snapshot컬럼).
2. 🔶 **m5_ja KO명 초안** `python/catalog_gapfill/m5_ja_ko_draft.csv`: 44장 중 **자동 32**(포켓몬 ex/메가ex/AR, ko_en_pokemon.json 역매핑)·**수동 12**(트레이너 SR=Iron Defender/Energy Switch/Crushing Hammer/Dark Bell/Heroic Bomb/Brave Bangle/Misty's Energy/Gladion's Decisive Battle/Rust Syndicate Grunt/Gwynn — 종족명 아님, 공식 KO명 큐레이션 필요).

## m5_ja(어비스아이) 추가 prep — 진행
- ★**KO 세트명 = 어비스아이** (slug abyss-eye, 사용자 확정)
- ✅ **이미지 44장 다운로드 완료** `python/catalog_gapfill/m5_ja_images/{jp_ref}.png` (scrydex medium, PNG ~120KB, 0실패). 용도=앱표시(S3미러 후보)+스캐너 FAISS 인덱싱.
- ★**카드타입 정정(scrydex 실확인)**: "트레이너 12"를 내가 뭉뚱그림 → 실제=**도구/아이템6(102 Iron Defender·103 Energy Switch·104 Crushing Hammer·105 Dark Bell·106 Heroic Bomb[포켓몬도구]·107 Brave Bangle[포켓몬도구])** + 특수에너지1(108 Misty's Energy) + 서포트(109/116 Gladion's Decisive Battle·110 Rust Syndicate Grunt·111/117 Gwynn).
- ★**사용자 지시=도구 제외**(아이템+포켓몬도구 6장 빼기) → **추가대상 44→38**(포켓몬32+서포트5엔트리+에너지1). 산출 `m5_ja_addlist.csv`(include 컬럼).
- 🔶 **KO명 아직 필요=6엔트리(4고유)**: Misty's Energy(특수에너지)·Gladion's Decisive Battle(SR109+SAR116)·Rust Syndicate Grunt(110)·Gwynn(SR111+SAR117). 포켓몬32는 자동확정(`m5_ja_ko_draft.csv`).

## ★★ prod↔로컬 정합 확정 (2026-06-20밤, prod 직접 접속)
- prod 접속: `ssh -i /Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120` → `docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db`. (내가 -i 키 빼고 테스트해서 "publickey denied" 오판했던 것)
- **prod 3755 (KO3728·JP26·EN1·숨김285) = 로컬 3755. card_id diff 0/0 → 완전 동일.** 6/19 snapshot은 필터 안 됐던 게 맞음.
- ★**결론(방향): 서버·로컬 둘 다 안 뒤쳐짐=동일. 낡은 건 스캐너 벡터 인덱스(card_meta/faiss)뿐.** ★**471 orphan 정확분해(prod 진본 대조)**: **243=카드는 prod에 있는데 인덱스가 옛 card_id(재import로 id바뀜)→옛id+새id 중복=스캐너 옛ID매칭→"안 뜸"의 진짜원인** / **228=진짜 prod에 없음(DP2010 H레어36·ACE31·UR55·후파EX/리자몽 등 옛카드=legacy삭제거나 누락갭 후보).** ("둘다없는 471"은 내 부정확표현, 정정). 현재카드 중 미인덱스 1(EN promo). 10벡터미만 161(160=이미지1장·1=0벡터).
- ★해법=prod-로컬 sync 아니라 **인덱스를 현재 3755 기준 재빌드**(471 stale청소+161보충+신규갭). 산출 `prod_cards_full_20260620.csv`(prod 진본).
- ★build_db.py augment=이미지1장당 5뷰(원본/밝게+55/어둡게-55/회전±7°)·`WHERE language='KO'`만 인덱싱·로컬DB조회. ∴카드당벡터=이미지수×5(jp만5·jp+en10·jp+en+ko15).

## ★ 228(prod에 진짜 없는 orphan) 분석 결론 — "넣을 거 거의 없음"
- 56 포켓몬후보 중 prod에 **아예없는 건 3장뿐**(알로라레트라GX SM-P·찬란한 히스이 포푸니크 샤이니볼트·채키몽 샤이니, 전부 niche). 나머지 53=**이미 prod에 다른판본 보유**(reprint, 가디안EX 21판본 등).
- 225 잔여=옛 2010 DP H레어48 + 트레이너 reprint(ACE/UR골드/SR, 프라임캐처 등 세트마다 중복) + alternate printing = **prod 의도적 미carry 카테고리**. 인덱스가 옛 dev DB에서 들고온 잔재.
- ★**결론: 228은 진짜 갭 아님 → 재빌드로 자동청소. prod 신규추가 불필요**(3장 niche 옵션). **진짜 신규 갭 = 어비스아이(m5)·m3/m4 빠진 것 = scrydex 트랙.**

## ★ (구) 인덱스 감사 — prod접속 전 추정, 위에서 확정됨
- FAISS 인덱스 4225장 / DB 3755 → **DB에 있는데 인덱스 없음=1장뿐**(피카츄 SWSH020 프로모 EN). "대량 미인덱스"는 사실 아님.
- 인덱스가 DB보다 **471장 많음=고아**(stale, prod에도 없음=예전삭제 잔존). 잠재적 오매칭원인·정리후보.
- ★**결론: 메가개굴닌자 098/114 "안 뜸"=로컬DB stale(이미 38장 sync로 해결), 인덱스 구멍 아님.** 기존카드 인덱스 정상.
- ★진짜 인덱스공백=신규 갭카드(m5_ja 등 미추가분)→**추가시 add→이미지→build_missing.py 인덱싱→검증 한묶음 필수**(098/114 재발방지).

## m5_ja POST 잔여
1. m5_ja POST 준비 잔여: ①트레이너 KO명 ✅완료(108이슬의기력·109/116글라디오의결전·110녹청파의조무래기·111/117무쿠) ②**product_id**(어비스아이 product prod에 없음→신규생성 필요)(KO 미발매=KO product 없음, m4_ja는 PRD_156BB71C4F5A41C39521 사용 — m5_ja용 product 생성/할당 결정 필요) ③이미지→스캐너 인덱싱(build_missing.py)+S3미러 여부 → `POST /api/admin/cards` 단건(승인후·prod write). m3/m4 트레이너SR 갭(7+9)도 같은 처리.
2. pokemoncard KO 트랙: JP-ref 디둡 + maxn 동적조정 후 재스캔.

## ★★ canary 실행 진행 (2026-06-21, prod write 시작)
- **product COMMIT 완료**: `PRD_1B9CC7C6D61653EEDEB28` = `MEGA 확장팩 「어비스아이」`(MEGA/BOOSTER/KO). dry-run(BEGIN→SELECT→ROLLBACK) 후 COMMIT, 7검증 통과.
- **canary 2장**(사용자 admin UI POST 대기): 메가다크라이 ex RR 046/081 m5_ja-46 + SAR 114/081 m5_ja-114. enScrydexRef/officialCardCode=null.
- **다음**: card_id 2개 받으면 → 백필 SQL dry-run(SCRYDEX_JP+KO_ESTIMATED[chart_price컬럼], 32hex id, card_id기준 롤백, NOT EXISTS 가드) → Codex/사용자/Claude 3중검수 → COMMIT → 앱차트+기존diff0 검증.
- ★백필 데이터=`m5_ja_chart_preview.csv`(532행, 실제 scrydex date+raw), canary 2장만 56row.
- ★admin POST는 admin JWT 필요→Claude 불가→사용자가 admin UI로(=enrich/이미지/오늘시세 실테스트). 백필만 Claude SQL.
- ★자동 sync 확인됨: price_scrydex.py(21:00 language=KO+jp_ref)→refreshKo(23:45)→v6_apply(23:52 KO)→chart_price(23:57). 신규 m5_ja 자동포함.
- 산출 artifacts: `python/catalog_gapfill/canary_*.sql/json`, `m5_ja_chart_preview.csv`.

## 금지: prod write·자동가격반영·v6/live·NAVER사용·bulk-insert(ref NULL). canary 외 36장·card insert·백필 아직 금지.
