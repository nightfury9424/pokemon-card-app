# 📋 새 세션 복붙용 — SNKRDUNK JP 가격 파이프라인 인수인계

> 이 파일 전체를 **새 Claude/ChatGPT 세션 첫 메시지에 그대로 복붙**하면 됨.
> (새 세션은 repo 문서/메모리를 자동으로 안 읽으므로 이 텍스트가 진입점.)

---

## ▶ 다음 세션 우선순위 = **⑤ 검수 UI (HIGH 10 하향부터)** — ①~④는 끝남 (2026-06-30)
★**①~④ dry-run 구현·검증·코드리뷰 통과 완료** (`python/price_v8/snk_pipeline/`). **다시 만들지 마라.**
현재 위치: `review_queue` 10건 PENDING_REVIEW(HIGH 10 STRONG_REPLACE, 라이브 수집으로 분석 재현) · prod write 0 · scrydex 불변 · 자동적용 0.

### 다음 세션 첫 지시문 (이렇게 말해라)
```
SNK 파이프라인 ①~④(저장스키마/승인게이트/collector/detector)는 dry-run 구현·검증 끝났다.
산출물 = python/price_v8/snk_pipeline/ (db.py·load_mapping.py·collector_dryrun.py·detector_dryrun.py·README.md),
로컬 snk_pipeline.sqlite 의 review_queue 에 HIGH 10 PENDING_REVIEW 적재됨. 절대 ①~④ 다시 만들지 마라.
이번엔 ⑤ 검수 UI 를 만든다 = review_queue(priority='HIGH' STRONG_REPLACE 먼저) 를 사람이 approve/reject 하는 로컬 화면.
저장은 review_queue.review_status 업데이트만(로컬 SQLite). prod write/가격반영 0. prod 접근은 승인 먼저.
먼저 README.md + detector_dryrun.py 읽고, 검수화면 필수표시 항목(설계서 ⑤)대로 설계 보여주고 시작.
```
- 진행률: ①저장스키마 ✅ ②approved 승인게이트 ✅ ③collector dry-run ✅ ④anomaly detector dry-run ✅ → **⑤ review queue/UI(HIGH 10 먼저)** ⑥override 가격선택레이어(GlobalPriceService) ⑦시뮬 ⑧운영반영(별도).
- 검수화면 필수표시(설계서 ⑤): 우리카드/SNK 이미지·카드명·SNK title·product_number·collection_number·rarity·scrydex RAW/PSA10/PSA9 vs SNK A/PSA10/PSA9·n(거래수)·ratio·usedMinPrice·수집일 + 버튼 approve_replace/reject_keep/hold/mapping_review.
- 운영 다듬기(⑥⑦ 전): 환율 prod SYSTEM 라이브 읽기(현재 06-29 하드코딩) · scrydex fresh 추출(현재 scrydex_jp_ladder_prod.csv 06-29 stale).
- LOW 62(상향·고위험)는 HIGH 10 끝난 뒤 별도 강한기준: n≥10 + 이미지/세트/번호 일치 + 체이스 확인.
- 병렬 백그라운드: Android closed test 승인·테스터 opt-in·14일 시계 (docs/ANDROID_RELEASE_HANDOFF_20260628.md). iOS 출시됨(모니터).

---

## SNKRDUNK JP 가격 파이프라인 상세

기준일: 2026-06-29 · 프로젝트: /Users/fury/pokemon-card-app

## 0. 현재 결론
SNKRDUNK 작업 = 단발성 가격 교정이 아님. **scrydex JP를 SNKRDUNK_JP로 감시·검증·보정하는 신규 가격 파이프라인.**
- scrydex JP 이상 카드 탐지 → SNK A/PSA10/PSA9 시계열로 검증 → 사람 승인 → approved override만 사용 → 매일 SNK 동기화.
- scrydex는 유지, SNK는 별도 source로 저장. 최종 가격선택 레이어에서 approved override만 반영.
- **설계+분석 완료 · 구현 전 · 운영반영 0 · DB write 0.**

## 1. 절대 원칙 (불변)
- scrydex 덮어쓰기 금지 · SNK는 별도 source(`SNKRDUNK_JP`) 저장
- ★**working/high-confidence mapping(3,313) ≠ approved mapping.** 매핑 *정확성*은 사람이 검수했으나 **가격 override용 운영-확정 매핑은 아님.** 파이프라인엔 별도 승인게이트 거친 approved만 사용. ("사람이 다 봤으니 approved"로 오해 금지)
- SNK 전면 대체 금지 · LOW 상향 후보 자동 적용 금지
- PSA10/PSA9를 raw에 혼입 금지 · `all(-1)` chart 사용 금지
- `usedMinPrice` = ASK 보조값(실거래 아님)
- 운영 반영 전 백업·rollback·dry-run 필수 · prod write/가격반영/sync·apply 금지
- ★prod(`pokemon_card_db`) 접근은 read-only도 **SELECT 쿼리 보여주고 승인 먼저**
- Android 작업과 SNK 작업 섞지 말 것

## 2. SNK API (확인됨)
```
A    : /v1/apparels/{id}/sales-chart/used?range=oneMonth|threeMonths&salesChartOptionId=18
PSA10: ...salesChartOptionId=22   PSA9: ...salesChartOptionId=23
detail: /v1/apparels/{id}   (usedMinPrice, listingCount)
points = [ts_ms, price_jpy]. 429/403 즉시중단·재개가능. all(-1)=18/22/23 외 혼합이라 금지.
```

## 3. 데이터 구조 (prod price_snapshots, 확인됨)
- scrydex JP RAW: `source='SCRYDEX_JP' AND card_status='RAW'` → `raw_price`+`raw_currency`(USD/JPY) → KRW 환산
- scrydex JP PSA10/9: `card_status='GRADED' AND grading_company='PSA' AND grade_value='10'/'9'` → **`price` 컬럼(이미 KRW)**
- 환율: price_snapshots SYSTEM `exchange_rate_usd`/`_jpy` ÷100 = (2026-06-29) **USD 1536.48 / JPY 9.50** KRW
- 정상 ladder = **PSA10 > PSA9 > RAW** (데이터 84%. 초기 "PSA10>RAW>PSA9" 가정은 오류)
- prod ssh: `ssh -i ~/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120` → `docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db`

## 4. 분석 결과 요약 (working mapping 3,314, ★approved 아님)
- SNK A usable(매핑의심 제외) 1,028 (A_1M 689 + A_3M 339), 견고 n≥5 = 472, scrydex only 1,953, mapping_review 172
- ladder anomaly 1,961 → STRONG 72 = **HIGH 10**(scrydex과대→하향, 저위험, 먼저) + **LOW 62**(scrydex과소→SNK 3배상향, 고위험, 자동금지)
- RAW_STALE_LOW 1,367 = graded premium라 정상가능 → 후순위
- 결론: SNK A 품질↑·커버리지↓. 전면대체 금지, A 거래충분(n≥5)만 approved override 후보. 나머지 scrydex fallback.

## 5. 산출물 (python/price_v8/, 분석 전용)
```
snk_price_full.csv · snk_vs_scrydex_jp_compare.csv · scrydex_jp_ladder_prod.csv
scrydex_jp_ladder_anomalies_raw.csv · _scored.csv
scrydex_jp_snk_replace_candidates_strong.csv · _down_first.csv(HIGH 10) · _up_review.csv(LOW 62)
```
백업: `~/pokefolio_backups/snk_ladder_analysis_20260629_1308/`
설계문서: `docs/SNK_PRICE_PIPELINE_DESIGN.md` (이게 정본, 더 상세)

## 6. 다음 세션 순서 (바로 구현 X)
```
0. 위 파일들 존재 확인 (ls)
1. SNK 저장 스키마 설계 (price_snapshots source='SNKRDUNK_JP' 추천)
2. approved mapping 테이블 설계 (working→approved 승인게이트)
3. daily collector dry-run (approved 샘플)
4. anomaly detector dry-run (정상 ladder PSA10>PSA9>RAW)
5. review queue/UI — ★HIGH 10(_down_first) 먼저, LOW 62는 n≥10+이미지/세트/번호일치+체이스확인 강한기준
6. approved override CSV
7. 가격선택 레이어 시뮬 (GlobalPriceService)
8. 운영 반영 = 별도 세션, 백업+승인 후
```

## 7. (참고) 새 세션 첫 확인 명령
```bash
cd /Users/fury/pokemon-card-app
ls -lh docs/SNK_PRICE_PIPELINE_DESIGN.md
ls python/price_v8/scrydex_jp_snk_replace_candidates_*.csv
ls ~/pokefolio_backups/snk_ladder_analysis_20260629_1308/
```
