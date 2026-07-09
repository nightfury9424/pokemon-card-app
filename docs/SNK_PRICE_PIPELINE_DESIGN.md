# SNKRDUNK_JP 가격 파이프라인 설계 (2026-06-29)

> **목적: scrydex JP를 SNKRDUNK 일본 실거래 데이터로 감시·검증·보정하는 신규 가격 소스 파이프라인.**
> 단발성 13/72장 교정이 아님. **덮어쓰기 금지** — scrydex 유지 + SNK 별도소스 + approved override만 가격선택 레이어에 반영 + 매일 동기화.
> 현재 = 분석/샘플 단계. **운영 반영 0 · DB write 0.** 진입점.

## 0. 핵심 원칙 (불변)
1. **scrydex 데이터 절대 덮어쓰지 않음.** SNK는 `source='SNKRDUNK_JP'` 별도 적재.
2. **approved override만 사용.** 현재 3,313 working/high-confidence 매핑 ≠ approved. 승인 게이트 필요.
3. **A = raw 주력 / PSA10·PSA9 = ladder 참고(raw 미혼입) / usedMinPrice = ASK 보조 / all(-1) 미사용.**
4. **상향은 보수적.** scrydex 과소→SNK 상향(LOW)은 고위험 → 강한 검수 후만.
5. **통화 정규화 필수** (USD×1536.48 / JPY×9.50 = KRW). GRADED price는 이미 KRW.
6. **운영 반영은 별도 세션, 백업+승인 후.** prod write 금지.

## 1. 컴포넌트 (6단)
### ① Approved Mapping 테이블
```
card_id · snkrdunk_apparel_id · mapping_status · mapping_confidence · approved_by · approved_at · notes
```
- 현재 `snkrdunk_working_mapping.csv`(3,313)는 **working**. → 승인 절차 거쳐 **approved만** 파이프라인 투입.

### ② SNK 일일 수집기 (approved만)
endpoint (카드당):
```
/v1/apparels/{id}/sales-chart/used?range=oneMonth&salesChartOptionId=18    # A (raw)
/v1/apparels/{id}/sales-chart/used?range=threeMonths&salesChartOptionId=18
... salesChartOptionId=22 (PSA10) · =23 (PSA9) 각 1m/3m
/v1/apparels/{id}                                                          # usedMinPrice, listingCount
```
- points = `[ts_ms, price_jpy]`. 429/403 시 즉시 중단·재개가능·중복방지. all(-1) 미수집.

### ③ SNK 스냅샷 저장 (별도 소스)
```
source='SNKRDUNK_JP' · tier(A/PSA10/PSA9) · price_krw · price_jpy · points_count · range(1m/3m) · basis(median/latest) · collected_at
```
- 추천: `price_snapshots`에 `source='SNKRDUNK_JP'` 추가 (기존 SCRYDEX_JP/EN과 동급). scrydex 행 불변.

### ④ 이상치 디텍터 (매일 scrydex vs SNK)
정상 ladder = **PSA10 > PSA9 > RAW** (데이터 84% 확인). 조건:
```
PSA10 < PSA9*0.9 (GRADED_INVERSION) · RAW > PSA10*1.1 (RAW_OVER_PSA10) · RAW > PSA9*1.2 (RAW_OVER_PSA9)
PSA10/RAW≥10 또는 PSA9/RAW≥5 (RAW_STALE_LOW=graded premium라 약함·후순위)
scrydex_RAW/SNK_A ≥2 (SNK_DIV_HIGH=하향) · ≤0.5 (SNK_DIV_LOW=상향·고위험)
```
→ 바로 적용 X, **review queue**로.

### ⑤ 검수 큐 (사람 승인)
상태: `PENDING_REVIEW / APPROVED_REPLACE_WITH_SNK / REJECTED_KEEP_SCRYDEX / HOLD / MAPPING_REVIEW`
검수화면 필수표시: 우리카드 이미지·SNK 이미지·카드명·SNK title·product_number·collection_number·rarity·scrydex RAW/PSA10/PSA9·SNK A/PSA10/PSA9·SNK 거래수(n)·ratio·usedMinPrice·최근수집일. 저장=SQLite/CSV (DB write 0).

### ⑥ 가격 선택 레이어 (override)
```
JP raw 선택: 1) approved SNK A override 있으면 SNK A  2) 없으면 scrydex JP RAW (fallback)
JP PSA10/PSA9: SNK 참고·비교용. raw 가격에 미혼입.
EN = scrydex 유지.
```
- 실제 구현 위치: `GlobalPriceService` JP raw 선택부에 approved-override lookup 삽입. **scrydex 행 보존.**

## 2. 현재 상태 (2026-06-29)
- ✅ working mapping 3,313 (high-confidence, **미승인**)
- ✅ SNK 전수 pull (A/PSA10/PSA9 1m+3m, `snk_price_full.csv`) — 분석용
- ✅ scrydex JP RAW/PSA10/PSA9 prod read-only 추출 (`scrydex_jp_ladder_prod.csv`, KRW정규화)
- ✅ 이상치 분석 (`scrydex_jp_ladder_anomalies_scored.csv` 1,961 · STRONG 72 = HIGH 10 down_first + LOW 62 up_review) — **파이프라인 검증용 샘플**
- ❌ 미구현: 승인 게이트 · 일일 수집기 · SNK 저장 스키마 · 디텍터 cron · 검수 큐 UI · override 레이어

## 3. 안전한 진행 순서 (로드맵)
```
1. 산출물 백업/문서화        ← 완료(본 문서 + ~/pokefolio_backups/snk_ladder_analysis_*)
2. 파이프라인 설계 문서        ← 본 문서
3. 로컬 daily collector dry-run (approved 샘플로)
4. 로컬 anomaly detector dry-run
5. review UI 승인/거절 테스트 (HIGH 10 down_first 먼저, LOW 62는 강한기준 별도)
6. approved override CSV 생성
7. 가격 계산 시뮬레이션 (override 반영 시 어떤 카드 얼마 변하는지)
8. 운영 반영 = 별도 세션, 백업+승인 후 (SNKRDUNK_JP source 적재 + GlobalPriceService override)
```

## 4. 미결정 (다음 세션 결정)
- 저장: `price_snapshots` source 추가 vs 별도 `snk_price_snapshots` 테이블 (추천=source 추가)
- 승인 게이트: 검수 UI에서 working→approved 승급 방식
- override 적용: GlobalPriceService 어느 지점 + 캐시(`cardPriceSummary`) 무효화
- 상향(LOW) 정책: n≥10 + 이미지/세트/번호 일치 + 체이스 확인 + KO 라이브가 충돌검사

## 5. 산출물 파일 (분석용·로컬)
```
snkrdunk_working_mapping.csv            working 매핑 3,313 (★approved 아님)
snk_price_full.csv                      SNK 전수 pull (A/PSA10/PSA9 1m+3m + usedMin)
snk_vs_scrydex_jp_compare.csv           SNK A vs scrydex JP 비교표 (3,314 × 32)
scrydex_jp_ladder_prod.csv              scrydex RAW/PSA10/PSA9 (prod read-only, KRW)
scrydex_jp_ladder_anomalies_raw.csv     이상치(점수 전)
scrydex_jp_ladder_anomalies_scored.csv  +replacement_confidence/floor_suspect
scrydex_jp_snk_replace_candidates_strong.csv     STRONG 72
  _down_first.csv (HIGH 10, scrydex과대→하향, 리스크낮음, 먼저)
  _up_review.csv  (LOW 62, scrydex과소→상향, 고위험, 강한검수)
backup: ~/pokefolio_backups/snk_ladder_analysis_20260629_1308/
```

## 6. 금지
72장 일괄 적용 · LOW 상향 자동적용 · DB write · 가격 반영 · sync/apply · 원본 CSV 덮어쓰기 · all(-1) 사용 · PSA를 raw에 혼입 · working을 approved처럼 사용.
