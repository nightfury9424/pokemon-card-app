# PRICE_MODEL_V8 — JP-sanity-first (설계안, 2026-06-19)

> **상태: 설계+dry-run만. 코드/prod/sync/apply/admin-add 전부 0.** v6는 오늘 23:45 un-freeze/live run 대기 — 건드리지 않음. v8은 `python/price_v8/` dry-run으로만.

## 1. 목적
현재 가격 앵커가 한국판 카드를 **양방향으로 틀리게** 산정한다.
- AR/GX(EN 프리미엄): EN 선택 → **과대평가** (리자몽 GX 표시 334k / jp 316k / en 1,019k)
- 릴리에류 grail(JP>>EN/싼 EN ref): EN 선택 → **과소평가** (릴리에 표시 116k / jp_raw 11.29M)

v8 목표 = `spread > threshold → EN` 구조를 **JP-sanity-first**로 대체. "무조건 JP"가 아니라 **JP 정상성 검증 → 자동/수동/EN fallback 분기.**

## 2. v6와의 차이 / 기존 spread guard 문제
`selectScrydexSnapshotForKo` 현재 구조:
```
JP 정상 + EN 존재 → high/low > threshold(2.0/2.2/1.8) → return EN
```
문제:
- **방향이 거꾸로** — JP 정상성 판단 *전에* spread만 보고 EN 선택.
- threshold(2.0~2.2)는 5/18 baseline 이전(ff552e71/11cfd60c)부터. **6/14 회귀 아님, 오래된 설계.**
- threshold 올려도 무의미 — 릴리에 16배·AR 4~8배는 여전히 EN.
- **`validation_status` 컬럼은 있는데 전부 VALID = sanity-check 미작동** (릴리에 raw 11.29M도 검증없이 통과).

## 3. JP-sanity-first 버킷 정의 (우선순위)
```
1. MANUAL_ANCHOR / MANUAL_FLOOR 있음        → 수동값 (최우선)
2. jp_raw 없음 / jp_ref 없음·NO_ / stale     → EN_FALLBACK_OK → EN
3. jp_raw > jp_psa10                         → RAW_OVER_PSA10_INVALID (JP_SUSPECT) → 자동 금지
4. jp_raw > jp_psa9                          → RAW_OVER_PSA9_SUSPECT (JP_SUSPECT)  → 자동 금지
5. jp_raw 있는데 jp PSA ladder 없음(검증불가)  → MANUAL_REVIEW → 자동 금지
6. (grail / en_ref 싼 다른카드 의심)          → MANUAL_REVIEW
7. else (jp_raw + ladder 통과)               → JP_VALID → JP
```
spread는 **EN 트리거 아님** — JP_SUSPECT 판정의 보조지표로만(옵션).

| 버킷 | 처리 | KO_ESTIMATED |
|---|---|---|
| MANUAL_ANCHOR/FLOOR | 수동값 | 수동값 |
| JP_VALID | JP anchor | jp_raw × jpCoef |
| EN_FALLBACK_OK | EN anchor | en_raw × enCoef |
| JP_SUSPECT | 자동 금지 | **미저장/기존유지** |
| MANUAL_REVIEW | 사람 검토 | **미저장/검수중** |

6/18 prod 재현(**정정 — 실제 dry-run 출력 기준, 아래 §8**): JP_VALID **2,359** · EN_FALLBACK_OK **1,043** · MANUAL_REVIEW **84** · JP_SUSPECT **247** · MANUAL_ANCHOR **8** (총 3,741).
> ⚠️ 이전 본문 숫자(2,093 / 1,046 / 354 / 248)는 **stale** — 초안 시점의 no-ladder 처리(모든 no-ladder→MANUAL_REVIEW) 기준이었음. 최종 스크립트는 no-ladder 중 `jp_raw>300,000원(GRAIL)`만 MANUAL_REVIEW, 나머지 저가 268장은 JP_VALID로 보냄 → MANUAL_REVIEW 354→84(−270), JP_VALID +266. 숫자 일치 검증됨.

## 4. MANUAL_REVIEW 처리 (핵심)
- **신규 카드 + MANUAL_REVIEW/JP_SUSPECT → KO_ESTIMATED 저장 X, "가격 검수중" 표시.**
- **기존 카드 + MANUAL_REVIEW → 마지막 정상값 유지 + manual queue.**
- 자동 EN(헐값) / 자동 JP(spike) 둘 다 금지. (릴리에를 116k도 11.29M도 안 함)
- grail(릴리에/블래키/리자몽/레쿠쟈/고가 SR/SAR/HR/MUR)은 manual_anchor/floor 큐로.

## 5. admin preview / add-time / nightly 공통화 (필수)
지금 경로별로 anchor decision이 다름 = 또 터지는 원인:
- preview/add-time(`calculateKoEstimatedForCard`): `selectScrydexSnapshotForKo(..., prevSource=null)` → threshold 2.0
- nightly(`refreshKoEstimatesFromSnapshots`): `prevSourceMap.get(cardId)` 전달
- python v6_apply: FROZEN_KOVALS/MANUAL 별도

**v8 = 단일 anchor decision 함수**를 preview·add-time·nightly가 모두 호출. 신규카드(prevSource 없음)도 같은 sanity 버킷 적용.

## 6. prod 적용 금지 상태 (오늘)
- 코드 수정 0 · GlobalPriceService 수정 0 · v6_apply 수정 0 · prod write 0 · sync/apply 0 · admin add 0.
- v8은 `python/price_v8/` dry-run + 산출물 CSV만.

## 7. 다음 검증 절차
1. v8 dry-run으로 6/18 bucket 재현 + 현재 대비 diff (v8_vs_current).
2. 신규 59장 v8 결과 (preview/add-time 정책 검증).
3. MANUAL_REVIEW/JP_SUSPECT 큐 검수.
4. 오늘밤 v6 live run 결과 확인.
5. **승인 후** 구현 — 단일 anchor 함수 + validation_status 활성화 + grade_value ladder check + MANUAL_REVIEW 큐 테이블 + 앱 "검수중" 표시.

## 우선순위
1. **신규 카드 add-time/preview 차단** (당장 위험): JP_VALID→JP, MANUAL_REVIEW/SUSPECT→검수중.
2. 기존 broad EN-over-selection 교정: JP_VALID인데 EN탄 카드 → JP 후보, MANUAL_REVIEW는 수동큐.
3. manual anchor 확장: grail 후보 큐.

## 8. 2026-06-19 existing-only 재감사 정정 (신규 59 제외, 기존 3,741장)
> 산출물: `/tmp/price_v8_existing_audit_20260619/` + `~/Downloads/price_v8_existing_audit_20260619.tar.gz`. 로컬 read-only, prod 무접속.

### 8-1. ★397 JP→EN 역방향 = 100% 데이터 파이프 아티팩트 (정책 문제 아님)
- 전이 행렬: EN→JP 921 / **JP→EN 397** / JP→NONE 190 / EN→NONE 129.
- 397 전수 분류 = **397/397 `B_PIVOT_DUMP_INCOMPLETE`.** `D`(JP raw 정상인데 EN行)·`A`(JP ref 없음)·`C`(genuine stale) **= 0**.
- 근거: 397장 모두 6/18 audit 가 **같은 날 JP raw(`selected_raw_price_krw`>0)를 실제 사용**했는데, 같은 날 graded 덤프(`prod_jp_en_raw_graded_0618.csv`)엔 그 jp_raw row 가 **없음** → staleness 아니라 **덤프 추출 불완전**. ref 도 전부 valid(예: 메가썬더볼트ex `m1s_ja-77`, selraw 2,700원).
- 실제 결과: v8_estimated **None(미산정) 377 / 재가격 20**(+30%↑ 7·−30%↓ 5). "397 EN 인플레"는 **틀린 프레이밍**.
- **함의: 입력 덤프가 불완전하므로 dry-run 의 모든 집계(2,359/247/84/921 등)가 오염.** v8 구현 결정 전 **입력 추출 재실행(완전한 raw 스냅샷) → dry-run 재산출** 필수. 게이트 D=0 이라 정책 로직은 진행 가능.

### 8-2. ★frozen/manual 충돌 — v8 이 frozen 185장 덮어씀
- 로컬 파싱: FROZEN_KOVALS **226** / MANUAL_ANCHOR **8** / MANUAL_FLOOR **1**.
- 현 v8_decide 는 MANUAL_ANCHOR(8)만 보호 → **FROZEN_KOVALS 226 중 185장에 v8 자동값을 부여(덮어씀).** 예: 리피아ex frozen 28,050 → v8 EN 112,691(4×).
- **우선순위 고정 필수: MANUAL_ANCHOR > MANUAL_FLOOR > FROZEN_KOVALS > v8 sanity bucket.** (트레이드오프: frozen 유지 시 185장이 6/14 상수에 묶여 v8 개선 제외 = 정적 기술부채 존속.)

### 8-3. PSA9 tolerance — strict 는 노이즈를 SUSPECT 로 오분류
- strict(`raw>psa9`) suspect **242** / `×1.10` **193**(−49 해제) / `×1.15` **162**(−80 해제). `raw>psa10` hard invalid = **1**(tolerance 무관).
- false-positive 실증: 포켓몬 브리더의 육성 raw 15,088 vs psa9 15,073 = **0.1% 초과**인데 strict 는 SUSPECT→미산정. 그우린차ex 0.3%, 카지 0.8% 등.
- **권고: PSA9 가드에 `×1.10~1.15` tolerance band(또는 PSA9 관측수 가드) 추가.** raw>PSA10 은 hard invalid 유지.

### 8-4. 정정된 게이트 판정
- 구현 차단 사유(`D`) **없음**. 단 **선결조건 3개**: ① dry-run 입력 덤프 완전성 수정 후 재산출, ② FROZEN 우선순위 추가, ③ PSA9 tolerance band. 신규 59 는 본 감사 제외(부록).

## 9. 2026-06-19 전수 sanity audit — GRAIL 고정값 단독 폐기, 복합 score (기존 3,741장)
> 397 감사는 **전이 슬라이스 1개**였지 전수조사 아님. v8 의 진짜 목적 = 레시라무처럼 **표시가/ladder 관계가 모순인 카드 전수 탐지**(금액 임계 아님). 산출물 `python/price_v8/v8_full_catalog_sanity.py` + `/tmp/price_v8_full_catalog_20260619/` + 번들.

### 9-1. ★레시라무 SR 055/053 BW = v8 이 반드시 잡아야 할 케이스 (검증 통과)
- CRD_3E0AD8CAAB4F44D5B183 / BS2011001055 / SR / BW. current anchor=**EN** ko **16,555** (앱 대표가 16,590 일치).
- stored 덤프 pivot = `{jp_raw: 1,882,000}` **뿐** — psa ladder 없음(앱 상세의 PSA10 $622/PSA9 $341 은 scrydex **live** fetch, 저장값 아님).
- **`RAW_OVER_PSA10` 룰로는 못 잡음**(저장 ladder 결측). 잡는 건 **ko/jp_raw=0.0088(0.88%) 비율 + 속성**: flags=`DISPLAY_UNDERPRICED_VS_JP_RAW|OLD_ERA_HIGH_RARITY|NO_LADDER_HIGH_VALUE|ICONIC` → **score 9 → MANUAL_REVIEW.** 자동 EN 16,555 송출 차단 ✓

### 9-2. ★고정 GRAIL 단독 = 실패. 복합 score 가 정답
- `RAW_OVER_PSA10_INVALID` **단독은 6장**만 잡음(psa10 39% 결측). 반면 복합 score 는 **MANUAL_REVIEW 193 + WATCH 333** surface.
- action 분포: OK_AUTO 2,981 / WATCH 333 / KEEP_FROZEN 219 / MANUAL_REVIEW 193 / KEEP_MANUAL_ANCHOR 8 / JP_SUSPECT_HOLD 6 / KEEP_MANUAL_FLOOR 1.
- 우선순위 적용: MANUAL_ANCHOR > MANUAL_FLOOR > FROZEN > (raw>psa10 hold) > score≥5 MANUAL_REVIEW > score≥3 WATCH > OK_AUTO.
- **display 비율 outlier 269장**(릴리에 ko12,507 vs jp_raw 7.06M=0.18%, 아세로라 0.23%, 뮤츠EX 0.29%, 블래키EX 0.71% … 전부 EN 앵커·GRAIL컷 회피). = 핵심 broken class.

### 9-3. score 룰 (고정+비율+속성 혼합)
- raw>psa10×1.05 → RAW_OVER_PSA10_INVALID(+5) / raw>psa9×1.15 → RAW_OVER_PSA9_SUSPECT(+3) / en_raw>en_psa10×1.05(+3)
- ko/jp_raw<0.03(+3) / ko/jp_psa9<0.03(+3) / ko/en_raw>1.0(+2) ← **레시라무·릴리에류 핵심**
- BW·XY·SM + 고레어(+2) / ladder없음+jp_raw≥10만(+2) / iconic(+1) / GRAIL_FIXED_NO_LADDER(보조 +1)
- score≥5 → MANUAL_REVIEW, ≥3 → WATCH. (조정가능 — 단일 고정값 의존 X)

### 9-4. GRAIL threshold 민감도 (보조 신호로만)
- no-ladder+jp_raw≥임계: 100k→**133** / 300k→**85** / 500k→**64** / 1M→**36**. 단일 고정값 선택이 자의적임을 입증 → score 의 보조항으로만.

### 9-5. ★★최상위 한계 — 덤프 불완전 = false-negative 다수 (audit 은 outlier '하한선')
- 커버리지: jp_raw 72% / jp_psa10 **61%** / jp_psa9 **45%** / en_raw **14%** / 가격데이터 전무 **865장(23%)**.
- '플래그 안 됨'='정상' **아님**. raw>psa10 이 6장뿐인 것도 psa10 39% 결측 탓. en_raw 14% → EN-overpriced 탐지 거의 불가(1장).
- **결론: 완전한 가격 덤프 재추출 → 재실행이 모든 수치의 전제.** 현 수치는 하한 추정. (397 감사와 동일 선결조건.)

### 9-6. ★RAW_OVER_PSA10 blind spot = 가장 깨끗한 룰이 고레어 377장에서 장님 (레시라무 실증)
- 앱 스크린샷(레시라무 SR 055/053 BW): JP **RAW $1,344.29 > PSA10 $622.91**(=2.16배, 논리위반) / KO 16,590. **하지만 stored 덤프엔 이 카드 jp_psa10 없음** → `RAW_OVER_PSA10` 검사 자체 불가. 앱은 scrydex **live fetch**(`getCardPriceSummary` 폴백)라서 보임.
- jp_raw 보유 2,695장 중: **jp_psa10 보유=2,318(검사가능, 위반 6) / jp_psa10 결측=377(BLIND).** blind 377 중 고레어 307·구세대 237·jp_raw≥30만 85. **"위반 6장"은 바닥값.**
- blind 377 = **broken class 핵심**(릴리에 ko116k/jp_raw11.3M=1.0%, 뮤츠EX 0.3%, 블래키EX 0.7%, 레시라무 0.88%(6위), M레쿠쟈 2.3% …). 전부 iconic·전부 KO 극저가·전부 RAW_OVER_PSA10 미검사. → 산출물 `v8_raw_over_psa10_blindspot.csv`(재추출 우선순위 score 정렬).
- live 주입 검증: raw $1344 > psa10 $622 → `RAW_OVER_PSA10_INVALID(+5)` 즉시 발화. **룰은 맞고 데이터가 굶음.**
- EN side도 모순: 앱 EN PSA10 **$3,703** vs JP PSA10 $622(6배 괴리·매핑의심), 현 KO는 의심 EN raw($118)×계수=16,555. **JP·EN 둘 다 신뢰 anchor 없음 = 검증불가 = MANUAL_REVIEW(≠EN 자동).**
- **★precondition 격상: v8/audit 은 PSA ladder 를 앱과 동일하게 live(또는 완전 graded 재덤프)로 소싱해야 함.** 안 그러면 RAW_OVER_PSA10 은 가장 위험한 고레어에서 무력. = **단순 '입력덤프 보강'이 아니라 ladder 소싱 경로 통일이 핵심 선결.**

## 10. v8 = 검열기 먼저 + USER_COMP_REQUIRED 큐 (② 스톱갭, 2026-06-19 밤)
> v8 은 **가격 확정기 아님 = 자동 분류/검열기 먼저.** JP·EN 둘 다 이상/ladder 없음/표시가 시장괴리 → 자동가격 금지 → 가격 검수중 → 사람(Claude)에게 comp 요청. 산출물 `v8_user_comp_required_queue.csv`(709) · `_top100.csv` · `v8_user_comp_request_template.md`.

### 10-1. 큐 (frozen/manual 보호 제외 709장)
- status: LADDER_BLIND 305 · DISPLAY_OUTLIER 204 · JP_SUSPECT 149 · OLD_ERA_GRAIL 50 · EN_SUSPECT 1.
- needed_user_evidence 빈도: KOREA_SOLD 512 · JP_PSA9_10 455 · JP_RAW_SOLD 408 · PSA_LADDER_VERIFY 306 · MANUAL_ANCHOR_VALUE 120.
- top = 릴리에·뮤츠EX·블래키·레시라무·레쿠쟈·리자몽(전부 SR, KO 1~3% of jp_raw). 레시라무=LADDER_BLIND priority14.
- recommended_action=USER_COMP_REQUIRED, display=가격 검수중(기존값 유지). 확신 카드만 자동.

### 10-2. JP comp 소스 = snkrdunk (스캐너 이미지매칭)
- `snkrdunk.com/search?brandIds=pokemon&searchCategoryIds=6/33&keywords=...` → 우리 스캐너(DINOv2+FAISS)로 리스팅 이미지→card_id 매칭.
- ★★**수집 등급 제한 필수: A급(raw NM 등가)+PSA9+PSA10 딱 3티어만.** B/C이하·PSA1~8·타등급사 버림(=corruption 주범 제거). **불변식 A≤PSA9≤PSA10 검증**, 깨지면 리스팅 outlier 제외.
- snkrdunk = scrydex 비거나 corrupt 일 때 2차 JP comp. 상세=§v8_user_comp_request_template.md.

### 10-3. 상태머신
SUSPECT/LADDER_BLIND/DISPLAY_OUTLIER → 자동금지+검수중 → USER_COMP_REQUIRED(snkrdunk A/PSA9/PSA10+한국체결) → 불변식통과 → MANUAL_ANCHOR_READY → MANUAL_ANCHOR(우선순위 최상). 다음=① ladder live 소싱 설계(앱 getCardPriceSummary 경로 통일, 설계만·prod호출 금지).

## 11. SNKRDUNK JP evidence source (2026-06-19 밤, 보조 검수 소스)
> SNKRDUNK = **JP manual evidence source (자동 산정 ❌ / 검수·수동앵커 보강 ✅).** 산출물 `v8_snkrdunk_evidence_queue.csv`(659, 전부 PENDING) · `v8_snkrdunk_match_review.csv` · `v8_snkrdunk_ladder_summary.md`.

### 11-1. 규약
- URL: `snkrdunk.com/search?brandIds=pokemon&searchCategoryIds=6/33&keywords=...&sort=popular`. 매칭=스캐너 이미지(image+jp_name+set_code+card_number+rarity 5개 전부 일치, 불일치=MISMATCH_CARD 폐기).
- ★수집 등급 **A급·PSA9·PSA10 딱 3개만.** 제외: PSA8↓·B/C급·BGS/CGC·중/영/한판·에러·미개봉·이름같고 번호다름.
- ★★**가격타입: 검색페이지=판매중 호가 → 기본 `ASK_ONLY`(참고만).** 상세 체결확인시만 `SOLD_VERIFIED` 승격. 자동 anchor엔 SOLD 우선.

### 11-2. snkrdunk_ladder_status
`LADDER_OK`(A≤PSA9≤PSA10) / `RAW_OVER_PSA10`(A>PSA10·자동금지) / `PSA9_OVER_PSA10`(자동금지) / `LADDER_INCOMPLETE`(일부결측) / `MISMATCH_CARD` / `PENDING`. 큐 컬럼: snkrdunk_url·match_status·a/psa9/psa10_price_jpy·ladder_status·evidence_grade·price_type.

### 11-3. 상태: 미수집(PENDING) — 값 조작 금지
snkrdunk 스크래핑 안 함(외부호출·스캐너 파이프=별도 빌드). 현 산출물=수집 워크리스트 구조(659장 전부 PENDING/ASK_ONLY). 실제 fetch=승인 후 ① ladder 소싱 빌드에서. 금지: snkrdunk 값 자동 전체 업데이트·prod write·admin add·sync/apply·v6/live.

## 12. v8 = evidence-based 모델 (Scrydex 의존 탈피, 2026-06-19 밤)
> v8 은 Scrydex 단독 정답 모델 아님. **여러 소스 evidence 수집 → 우리 카드 매핑 → 신뢰도 판정 → 자동/검수/수동 분류.** Scrydex = 정답 아니라 **비교 대상**. 산출물 `price_evidence_external_schema.sql` · `v8_jp_ladder_by_card.csv` · `v8_scrydex_vs_snkrdunk_diff.csv` · 빈템플릿 3(raw/mapped/match_candidates, PENDING_SCRAPE).

### 12-1. Scrydex 단독 의존 불가 (수치 증명)
- Scrydex JP ladder_status: **LADDER_OK 1,625(43%)** / NO_DATA 1,046 / LADDER_INCOMPLETE 1,008 / **PSA9_OVER_PSA10 56** / RAW_OVER_PSA10 6. → **57%가 Scrydex만으론 ladder 불완전/없음/위반.**
- scrydex_vs_snkrdunk_diff = **Scrydex 의심 302장**(KO_UNDER_JP_PSA9 204·KO_UNDER_JP_RAW 67·PSA9_OVER_PSA10 56·RAW_OVER_PSA10 6) → SNKRDUNK 교차검증 대상.

### 12-2. 소스 우선순위 (Scrydex=4순위로 강등)
1 한국 최근 체결가 / 2 SNKRDUNK SOLD A·PSA9·PSA10 / 3 eBay·PSA sold / 4 Scrydex raw·graded(참고) / 5 ASK_ONLY(자동금지).
- **교차밴드: |Scrydex−SNKRDUNK| ≤25% = CROSS_AGREE(자동후보) / >25% = CROSS_CONFLICT → USER_COMP_REQUIRED.** (밴드 없으면 큐 폭발.)

### 12-3. ★기간 정책 (sold_date 필수 — 핵심 의존성)
- 기본 = 최근 60일 SOLD_VERIFIED. recency_bucket: SOLD_0_60D(HIGH·자동) / 61_90D(MEDIUM·보조) / 91_180D(LOW·수동) / 181_365D(REFERENCE_ONLY) / 365D+(HISTORICAL_ONLY·자동금지) / ASK_CURRENT(TTL14d·자동금지) / ASK_STALE(IGNORE).
- 확장: 60일 sold<2건 → 90일, 고가/구세대/iconic만 180일, grail은 365일 참고+MANUAL_REVIEW 유지.
- ★**현 로컬 Scrydex 덤프엔 traded_at/sold_date 없음 → recency 는 sold_date 있는 데이터(SNKRDUNK 상세·eBay·한국체결) 유입 후에야 작동.** = 아키텍처 의존성.

### 12-4. price_evidence_external (설계 ONLY)
별도 evidence 테이블(Scrydex 덮어쓰기 X). grade∈{A,PSA9,PSA10}·price_type∈{SOLD_VERIFIED,ASK_ONLY}·SOLD면 sold_date NOT NULL 강제. DDL=`price_evidence_external_schema.sql`. **적용 금지(prod write·마이그 실행 X, 승인+수동마이그 후).**

### 12-5. 상태
SNKRDUNK 미스크래핑(값 전부 PENDING, 빈템플릿). 로컬 산출=Scrydex baseline+스키마+큐 구조뿐. 금지: snkrdunk값 자동 전체업뎃·Scrydex 덮어쓰기·prod write·sync/apply·admin add·신규59·v6/live. 다음=① 스캐너 이미지매칭 파이프라인 설계(승인 후 fetch).
