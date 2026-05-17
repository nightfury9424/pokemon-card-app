# 세션 현황 — 2026-05-09 (2차 세션 포함)

## 오늘 완료된 작업 (1차 세션)

- [x] `refreshKoEstimatesFromSnapshots` 버그 수정 → `saveKoEstimatedSnapshots`에 위임 (강제 덮어쓰기)
- [x] `buildNativeResult` 수정 → KO_ESTIMATED primary, 없으면 live calc fallback
- [x] `getCardPriceSummary` 수정 → KO_ESTIMATED 우선 읽기
- [x] 가격순 정렬 쿼리 수정 → `KO_ESTIMATED` JOIN 기준 정렬 (SCRYDEX×계수 제거)
- [x] 리스트/상세 가격 불일치 해결 (KO_ESTIMATED 단일 소스)
- [x] scrydex 오염 방어 (`price_scrydex.py` guard, eBay 교차검증 구조)
- [x] `price_anomalies` 테이블 + 어드민 alerts 페이지
- [x] 스프레드 가드 수정: EN/JP > 2x 시 EN 반환
- [x] **버그 1 수정 (Java)**: `rawKrw()` null fallback 추가 — raw_price NULL이면 price(KRW) 사용
- [x] **버그 1 수정 (Python)**: `insert_snapshot()`에 raw_price/raw_currency 추가
- [x] **버그 4 수정**: `findPromoExclusiveOrderByPriceDesc` JP COALESCE fallback 추가
- [x] **동기화 스케줄러 전면 정리** (`PriceSyncScheduler.java`)
- [x] **히드런 V / 오리진 펄기아 V 이름 스왑 DB 수정**

---

## 오늘 완료된 작업 (2차 세션)

### 데이터

- [x] **JP RAW 백필** — 114장 대상, 69장 신규 삽입 (`backfill_missing_raw.py`)
- [x] **이상 JP 데이터 10건 삭제** — scrydex가 잘못 준 cap 초과 데이터 (PSA가격이 RAW로 수집된 것 추정)
  - 삭제 기준: 레어도별 cap (HR: 200만, SR: 500만, 기타: 300만 KRW) 초과 SCRYDEX_JP RAW 스냅샷
- [x] **`name_locked` DB 컬럼 추가** (`cards` 테이블, BOOLEAN DEFAULT FALSE)
- [x] **히드런 V / 오리진 펄기아 V name_locked = TRUE 설정**
- [x] **`currency` 컬럼 DROP** (`price_snapshots` 테이블 — 항상 KRW였던 dead column)

### Java 백엔드

- [x] **계수 fallback 불일치 수정** (핵심 버그):
  - `saveKoEstimatedSnapshots`가 `globalCoefficient`(0.495) fallback 사용 → `en_GLOBAL`(0.336) / `jp_GLOBAL` fallback으로 교체
  - 효과: 레쿠쟈 VMAX KO 예상가 607,170원 → 412,510원 (차트 값과 일치)
- [x] **KO_ESTIMATED upsert** — 전체 삭제 → 오늘자만 삭제 (`deleteTodayKoEstimated`) → 과거 히스토리 보존
- [x] **EN/JP 차트 raw_price/rawCurrency 반환** — `ChartPoint` 레코드에 필드 추가
- [x] **`currency` 필드 전체 제거** (PriceSnapshot, PriceSnapshotDto, PriceController, GlobalPriceService)
- [x] **`PriceSyncScheduler` 경로 교체** — `/tmp/` 구형 스크립트 → `python/` 프로젝트 경로

### Python

- [x] **`sync_cards.py` name_locked 체크** — name_locked=TRUE 카드는 name 필드 업데이트 스킵
- [x] **`/tmp/` 스크립트 3개 → `python/` 이동** (버전 관리 하에 넣음)
  - `/tmp/recalc_coefficients.py` → `python/recalc_coefficients.py`
  - `/tmp/naver_cafe_auction_scraper.py` → `python/price_naver_cafe.py`
  - `/tmp/ko_promo_price_scraper.py` → `python/price_promo_ebay.py`
- [x] **`regenerate_ko_estimated()` 함수 삭제** (`recalc_coefficients.py`) — Python이 KO_ESTIMATED 생성하는 경로 완전 차단
- [x] **모든 Python INSERT에서 `currency` 컬럼 제거** (price_scrydex, price_naver_cafe, price_promo_ebay, recalc_coefficients)
- [x] **PSA ordering validation 강화** (`sanitize_raw`):
  - RAW > PSA10 → 제거 (이전: × 1.3 허용)
  - PSA10 < PSA9 → 엄격 체크 (이전: × 0.5 허용)
  - PSA10 < RAW → PSA10 의심 처리 추가

---

## 스케줄러 타임라인 (PriceSyncScheduler.java)

| 시간  | 작업 |
|-------|------|
| 00:00 | scrydex 해외 시세 수집 (`price_scrydex.py`) + 프로모 eBay |
| 00:30 | 네이버 카페 낙찰가 수집 (1회/일) |
| 01:15 | 레어도별 계수 재계산 (`recalc_coefficients.py`, KO_ESTIMATED 안 씀) |
| 01:30 | Java 글로벌 계수 재계산 |
| 01:45 | Java EN/JP 비율 재계산 |
| 02:00 | **Java KO_ESTIMATED 최종 재계산** (단일 경로) |

---

## 미해결 이슈

### 🟡 이슈 A — NO_REMAP 카드 3장 scrydex ref 미완료
- 메가눈여아 ex (BS2025015036): `NO_m2a_ja-36_REMAP`
- 메가아쿠스타 ex (BS2026002021): `NO_m3_ja-21_REMAP` / `NO_me3_REMAP`
- 마오 (BS2017005055): `NO_sm2_ja-55_REMAP`
- **수정 방법**: `scrydex_mapper.html`로 정확한 ref 찾아 직접 업데이트

### 🟢 이슈 C — DC1 카드 KO 예상가 과대추정 — 완료
- DC1 (Double Crisis) en_scrydex_ref 기반 별도 era "DC1" 도입
- `resolveEraFromCard(Card)` 추가: dc1- prefix → "DC1" era
- DB에 `ko_coef_en_DC1_RR = 0.12` 삽입
- 결과: 22.9만 → 8.2만원 (재시작 후 refresh 필요)

### 🟡 이슈 B — 버그 3: stale KO_ESTIMATED 잔존
- **문제**: 계산 실패 카드는 오늘자 KO_ESTIMATED가 생성 안 됨 → 과거 stale 값 그대로 표시
- **수정**: 재계산 대상 전체에 대해 오늘자 먼저 정리 후 새 값 삽입

---

## 현재 KO 예상가 계산 플로우 (정상 상태)

```
price_scrydex.py 수집 (00:00)
    → SCRYDEX_EN/JP 스냅샷 저장 (raw_price/raw_currency 포함)
    → refresh-ko-estimates 자동 호출

recalc_coefficients.py (01:15)
    → 레어도별 계수 재계산 (KO_ESTIMATED 안 씀)

Java 스케줄러 02:00 → refreshKoEstimates()
    → saveKoEstimatedSnapshots()
        → selectScrydexSnapshotForKo()
            - JP rawKrw() null → price(KRW) fallback
            - JP not suspect + EN/JP < 2x → JP × jp_coeff
            - EN/JP > 2x → EN × en_coeff
            - JP suspect (cap 초과 / ratio 이상) → EN × en_coeff
            - fallback: en_GLOBAL / jp_GLOBAL (0.336 / 0.357)  ← 수정됨
        → 오늘자 KO_ESTIMATED만 삭제 후 재삽입 (히스토리 보존)  ← 수정됨

리스트/상세/차트 모두 KO_ESTIMATED 단일 소스
```

---

## 데이터 품질 guard 구조

| guard | 위치 | 조건 |
|-------|------|------|
| JP raw cap | Java `isJpRawSuspect` | HR>200만, SR>500만, 기타>300만 KRW |
| JP/EN ratio | Java `isJpRawSuspect` | JP/EN > 8x |
| EN/JP spread | Java `selectScrydexSnapshotForKo` | EN/JP or JP/EN > 2x → EN 사용 |
| RAW > PSA10 | Python `sanitize_raw` | RAW > PSA10 → 제거 |
| PSA10 < PSA9 | Python `save_history` guard | 엄격 체크 → PSA10 저장 스킵 |
| PSA10 < RAW | Python `save_history` guard | PSA10 avg < RAW avg × 0.9 → 의심 |
| eBay 교차검증 | Python `save_history` guard | PSA10 이상 감지 시 eBay 확인 |

---

## 계수 구조 (era-aware)

| 키 패턴 | 예시 | 설명 |
|---------|------|------|
| `en_{era}_{rarity}` | `en_SM_SR` (0.15) | EN scrydex era별 레어도 계수 |
| `en_{rarity}` | `en_SR` (0.657) | EN scrydex 레어도 계수 (era 무관) |
| `jp_{era}_{rarity}` | `jp_BW_HR` (0.04) | JP scrydex era별 계수 |
| `jp_{rarity}` | `jp_SR` (0.360) | JP scrydex 레어도 계수 |
| `en_GLOBAL` | 0.336 | EN fallback (레어도별 없을 때) |
| `jp_GLOBAL` | 0.357 | JP fallback |

`applyEraCap`: SCRYDEX_EN + SR + BW(0.10)/XY(0.15) era cap 적용
