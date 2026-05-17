# 시세 시스템

## 시세 종류

| 종류 | source 값 | 설명 |
|------|-----------|------|
| KO 예상가 | `KO_ESTIMATED` | scrydex EN/JP × 환율 × 레어도별 계수 |
| EN 시세 | `SCRYDEX_EN` | scrydex 영문판 RAW/PSA10/PSA9 |
| JP 시세 | `SCRYDEX_JP` | scrydex 일본판 RAW/PSA10/PSA9 |
| 네이버 카페 | `NAVER_CAFE` | 카페 낙찰가 (계수 재계산 소스, 표시 안 함) |
| 번개장터 | `BUNJANG` | 번개장터 실거래가 |
| eBay | `EBAY` | 프로모 카드 eBay 시세 |

---

## price_snapshots 테이블

```sql
price_snapshot_id  -- UUID
card_id            -- 카드 ID
source             -- 위 종류 참조
price              -- 원화 환산가 (KRW)
raw_price          -- 원본 가격 (USD/JPY/KRW 원값)
raw_currency       -- 'USD' | 'JPY' | 'KRW'
card_status        -- 'RAW' | 'GRADED'
grading_company    -- 'PSA' | 'BRG' | null
grade_value        -- '10' | '9' | null
traded_at          -- 거래/수집 날짜
collected_at       -- DB 저장 시각
```

> `currency` 컬럼은 2026-05-09 DROP (항상 KRW였음, dead column)

---

## KO 예상가 계산 플로우

```
매일 00:00: price_scrydex.py
  → SCRYDEX_EN / SCRYDEX_JP RAW 스냅샷 저장
    - price: 원화 환산 (USD × usd_krw, JPY × jpy_krw)
    - raw_price: 원본값 (USD 또는 JPY)
    - raw_currency: 'USD' 또는 'JPY'

매일 01:15: recalc_coefficients.py
  → NAVER_CAFE 낙찰가 기반 레어도별 계수 재계산
  → DB: price_snapshots WHERE source='SYSTEM', card_id='ko_coef_{key}'

매일 02:00: Java PriceSyncScheduler → refreshKoEstimates()
  → saveKoEstimatedSnapshots()
  → 오늘자 KO_ESTIMATED 삭제 후 재삽입 (과거 히스토리 보존)
```

---

## KO 예상가 소스 선택 로직 (selectScrydexSnapshotForKo)

```
JP 스냅샷 있음?
  └─ isJpRawSuspect?
       - raw_price NULL → suspect
       - JP/EN ratio > 8x → suspect
       - 레어도 cap 초과 (HR: 200만, SR: 500만, 기타: 300만 KRW) → suspect
     │
     ├─ suspect → EN 사용
     └─ not suspect:
          EN/JP or JP/EN > 2x?
          ├─ Yes → EN 사용
          └─ No  → JP 사용 (우선)

JP 스냅샷 없음 → EN 사용
```

---

## 계수 구조 (era-aware)

계수는 `price_snapshots` 테이블에 `source='SYSTEM'`으로 저장됨.
`card_id = 'ko_coef_{key}'`, `price = round(계수 × 10000)`.

| key 패턴 | 예시 값 | 설명 |
|----------|---------|------|
| `en_GLOBAL` | 0.336 | EN fallback (레어도별 계수 없을 때) |
| `jp_GLOBAL` | 0.357 | JP fallback |
| `en_{rarity}` | `en_SR`=0.657 | EN 레어도별 계수 |
| `jp_{rarity}` | `jp_SR`=0.360 | JP 레어도별 계수 |
| `en_{era}_{rarity}` | `en_SM_SR`=0.15 | EN era별 레어도 계수 |
| `jp_{era}_{rarity}` | `jp_BW_HR`=0.04 | JP era별 레어도 계수 |

**era 분류**: BW / XY / SM / SWSH / SV  
**특수 era**: DC1 — Double Crisis 영문 세트 (en_scrydex_ref `dc1-` prefix 기반, `resolveEraFromCard`가 판별)  
**applyEraCap**: EN + SR + BW(≤0.10) / XY(≤0.15) 상한 적용

---

## PSA 가격 데이터 품질 원칙

**PSA10 > RAW > PSA9** 순서 위반 시 해당 데이터 의심.

| 체크 | 위치 | 처리 |
|------|------|------|
| RAW > PSA10 | Python `sanitize_raw` | RAW 데이터 제거 |
| PSA10 < PSA9 | Python `save_history` guard | PSA10 저장 스킵 |
| PSA10 < RAW×0.9 | Python `save_history` guard | PSA10 저장 스킵 |
| JP raw cap 초과 | Java `isJpRawSuspect` | JP 무시 → EN fallback |
| eBay 교차검증 | Python `save_history` guard | 이상 감지 시 eBay 확인 후 결정 |

---

## 동기화 스케줄러 (PriceSyncScheduler.java)

| 시간  | 스크립트 | 역할 |
|-------|----------|------|
| 00:00 | `python/price_scrydex.py` | scrydex EN/JP 수집 |
| 00:00 | `python/price_promo_ebay.py` | 프로모 eBay 수집 |
| 00:30 | `python/price_naver_cafe.py` | 네이버 카페 낙찰가 |
| 01:15 | `python/recalc_coefficients.py` | 레어도별 계수 재계산 |
| 01:30 | Java `recalculateCoefficient()` | 글로벌 계수 갱신 |
| 01:45 | Java `recalculateEnJpRatios()` | EN/JP 비율 갱신 |
| 02:00 | Java `refreshKoEstimates()` | KO_ESTIMATED 최종 재계산 |

> **원칙**: KO_ESTIMATED는 Java만 생성. Python은 RAW 수집 전담.

---

## 프론트엔드 표시 규칙

- 대표가: `KO_ESTIMATED` 최신값 (없으면 scrydex live 계산)
- 범위: 대표가 × 0.85 ~ × 1.15
- 가격 포맷: 10원 단위 반올림 + 콤마 + "원"
- **KO 차트**: `KO_ESTIMATED` 히스토리에서 직접 읽음 (2장 이상일 때) — 대표가와 완전 일관성
  - 히스토리 부족 시 fallback: SCRYDEX EN/JP × era-aware 계수 live 계산
  - 히스토리 현황: 2026-04-26 ~ 현재 (backfill 완료)
- EN/JP 차트: `raw_price`(원본값) + `raw_currency`(USD/JPY) 별도 반환

---

## 어드민 엔드포인트

| 엔드포인트 | 설명 |
|-----------|------|
| `POST /api/prices/admin/backfill-ko-history?days=N` | 과거 N일치 KO_ESTIMATED 히스토리 백필 (이미 있는 날짜 스킵) |
| `POST /api/prices/admin/recalc` | 계수 재계산 후 KO_ESTIMATED 전량 재계산 |
| `POST /api/prices/admin/fetch-live` | 전체 카드 scrydex live 조회 → 스냅샷 저장 |
