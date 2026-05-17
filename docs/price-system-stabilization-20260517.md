# 시세 시스템 1차 안정화 — 인수인계 문서

> **핵심 원칙**: 급상승/급하락은 "산출 정책 변경"이 아니라 "실제 원천 데이터 변동"만 보여준다.

---

## 1. 문서 개요

- **작성일**: 2026-05-17
- **작업 목적**: KO_ESTIMATED 산출 audit화 + 급상승/급하락 랭킹 정확도 개선 + market_segment 도입
- **현재 상태 한 줄 요약**:
  > 시세 1차 안정화 완료. SWSH_SR_SUPPORTER만 market_segment 계수 적용 완료. 나머지 5개 segment는 한국 RAW 체결가 부족으로 fallback 유지.

---

## 2. 이번 작업의 핵심 결론

- ✅ Audit 기반 산출 추적 시스템 구축 (`ko_estimation_audit` 테이블)
- ✅ `ranking_eligible` 기반 급상승/급하락 필터링 적용 (계수 변경/저가/anomaly 자동 차단)
- ✅ Recent ranking API 분리 (오늘 엄격 vs 14일 window UX 안정)
- ✅ SWSH SR/HR 461장 market_segment 6종 분리 + DB import 완료
- ✅ SWSH_SR_SUPPORTER 계수만 실제 적용 완료 (JP/EN 각 1건씩, 총 2건)
- ✅ 14일 force backfill 완료 (51,696 KO + 51,696 audit)
- ✅ 랭킹 오염 없음 확인 (top-gainers/losers/recent-gainers 검증)
- ✅ 백업 보존 (rollback 경로 확보)
- 📋 **다음 단계**: P1/P2 Special Art 한국 RAW 체결가 수집 (사용자 수동 작업)

---

## 3. 최종 KO_ESTIMATED 산출 흐름

```
[1] SCRYDEX JP/EN raw 가격 수집
       ↓
[2] 산출 대상 카드 선정
    - findAllLatestScrydexEn / findAllLatestScrydexJp (refresh)
    - 또는 staleness 30d 윈도우 (backfill)
       ↓
[3] source 선택 (selectScrydexSnapshotForKo)
    - JP/EN spread + hysteresis (SPREAD_BASE 2.0, SPREAD_TO_EN_FROM_JP 2.2, SPREAD_TO_JP_FROM_EN 1.8)
    - prev source carry로 source flip 차단
       ↓
[4] 카드별 coefficient 결정 (priority chain 5단계)
    1. CARD coef     ← ko_price_coefficients scope=CARD (89장 보유)
    2. MARKET_SEGMENT ← card_market_segment_overrides + ko_coef_jp/en_{segment_key}
    3. ERA_RARITY    ← rarityCoeffs[sourceKey_eraKey_rarityKey] (현재 dead code 상태)
    4. RARITY        ← rarityCoeffs[sourceKey_rarityKey] (generic SR/HR 등)
    5. GLOBAL        ← rarityCoeffs[en_GLOBAL/jp_GLOBAL] fallback
       ↓
[5] applyEraCap (RARITY/GLOBAL/MARKET_SEGMENT에만 적용, CARD는 cap 없음)
       ↓
[6] koPrice = round(toLatestKrw(src) × coeff)
       ↓
[7] price_snapshots 저장 (source='KO_ESTIMATED')
    + ko_estimation_audit 저장 (1:1, FK CASCADE)
       ↓
[8] determineRankingExclusionReason 14단계 우선순위로 ranking_eligible 판정
       ↓
[9] 급상승/급하락 API 노출 (audit JOIN + ranking_eligible=true만)
```

**산출 방식 분기**:
- 일반 카드: 위 흐름 (CARD/MARKET_SEGMENT/RARITY/GLOBAL)
- 프로모 (is_promo_exclusive=true): `PROMO_DIRECT` (raw KRW 그대로) 또는 `PSA10_FALLBACK` (PSA10 가격 그대로)
- KO 독점 promo (NO_EN/NO_JP): `savePromoKoEstimatedFromKream` 별도 처리 (audit 미생성)

---

## 4. Audit 시스템 정리

**테이블**: `ko_estimation_audit` (PK: id UUID, FK: ko_snapshot_id → price_snapshots CASCADE)

**저장되는 핵심 값**:

| 컬럼 | 의미 |
|---|---|
| `selected_source` | JP / EN / PROMO_DIRECT / PSA10_FALLBACK |
| `selected_raw_snapshot_id` | 산출에 사용된 raw snapshot ID |
| `selected_raw_price_native` | raw 가격 (native currency) |
| `selected_raw_price_krw` | KO 산출에 실제 사용된 KRW 환산값 |
| `coef_scope` | CARD / MARKET_SEGMENT / RARITY / GLOBAL |
| `coef_key` | 실제 lookup key (예: `jp_SWSH_SR_SUPPORTER`, `jp_SR`, `CARD:CRD_xxx:JP`) |
| `coef_value` | 적용된 coefficient (applyEraCap 후 final value) |
| `raw_changed` | native raw price ≥0.5% 변동 여부 |
| `coef_changed` | 어제 audit과 coef_scope/key/value 비교 |
| `exchange_rate_changed` | USD/JPY 환율 ≥0.1% 변동 |
| `is_anomaly` | raw로 설명 안 되는 KO 급변 (15%+ raw_unchanged 또는 30%+ large move) |
| `anomaly_reason` | KO_MOVE_NO_RAW_EVIDENCE / KO_RAW_MISMATCH |
| `ranking_eligible` | 급상승/급하락 랭킹 후보 여부 |
| `ranking_exclusion_reason` | 14단계 우선순위 reason (NO_PREV_AUDIT, FALLBACK_SOURCE, LOW_PRICE, ZERO_CHANGE, MICRO_CHANGE, ANOMALY, SOURCE_CHANGED, COEF_CHANGED, FX_ONLY_CHANGE, NO_SELECTED_RAW, NO_PREV_RAW, RAW_UNCHANGED, KO_RAW_MISMATCH) |

**핵심 원칙**:
- **계수 변경은 시장 변동이 아니므로 `ranking_eligible=false` 처리**
- `coef_changed=true` AND `raw_changed=false` → `COEF_CHANGED` 또는 `ANOMALY` 분류 → 랭킹 제외
- `is_anomaly`와 `ranking_exclusion_reason`은 별도 컬럼 — anomaly여도 다른 reason이 더 적절하면 그쪽 우선 (FALLBACK_SOURCE가 ANOMALY보다 위)

---

## 5. 급상승/급하락 정책

### 오늘 랭킹 (엄격)
```
GET /api/cards/market/top-gainers?size=N
GET /api/cards/market/top-losers?size=N
```
- 오늘 vs 어제 KO 가격 비교
- audit INNER JOIN + `ranking_eligible=true AND is_anomaly=false`
- 5000원/100원/0.1~30% 보조 안전망
- **raw 변동 없는 날엔 빈 리스트가 정상** (cyclic error 차단)

### Recent 랭킹 (14일 window UX 안정)
```
GET /api/cards/market/recent-gainers?days=14&size=100
GET /api/cards/market/recent-losers?days=14&size=100
```
- `CURRENT_DATE - (:days - 1)` 범위 (오늘 포함 N일)
- `ranking_eligible=true` row 중 `DISTINCT ON (card_id)` + `ORDER BY change_pct DESC/ASC`
- 카드당 가장 큰 변동 1건만 노출
- 응답에 `currentPrice` (최신 KO) + `moveDatePrice` (변동일 가격) + `prevPrice` + `moveDate` 분리

### 자동 제외 케이스
| reason | 의미 |
|---|---|
| NO_PREV_AUDIT | 어제 audit 없음 (backfill 첫날 등) |
| FALLBACK_SOURCE | PROMO_DIRECT/PSA10_FALLBACK (랭킹 후보 아님) |
| LOW_PRICE | ko_price < 5000원 또는 prev < 5000원 |
| ZERO_CHANGE | 가격 동일 |
| MICRO_CHANGE | diff < 100원 |
| ANOMALY | raw로 설명 안 되는 KO 급변 |
| SOURCE_CHANGED | JP↔EN source 바뀜 |
| COEF_CHANGED | 계수만 바뀜 (이번 작업의 SUPPORTER 변경 차단) |
| FX_ONLY_CHANGE | 환율만 바뀜 |
| RAW_UNCHANGED | raw 그대로인데 KO만 변동 |
| KO_RAW_MISMATCH | 30%+ 큰 변동인데 raw와 매치 안 됨 |

---

## 6. Market Segment 작업 결과

| segment | 카드 수 | obs (JP/EN) | 상태 | 결정 사유 |
|---|---|---|---|---|
| **SWSH_SR_FULLART** | 152 | 0 | NO_DATA / fallback | KO 거래 0건 (저가 SR — 5000원 필터 안 잡힘) |
| **SWSH_SR_SUPPORTER** | 109 | 33/29 | ✅ **APPLIED** | JP 0.2765, EN 0.8945 적용 완료 |
| SWSH_SR_SPECIAL_ART | 41 | 8/8 | SHRINK 후보 / 보류 | obs 부족 (15+ 필요) |
| SWSH_HR_RAINBOW | 77 | 11/10 | SHRINK 후보 / 보류 | obs 부족 |
| SWSH_HR_SPECIAL_ART | 11 | 4/4 | sample 부족 / fallback | 11장 자체가 적음 |
| SWSH_HR_SUPPORTER | 71 | 1/1 | sample 부족 / fallback | outlier 위험 (1 obs) |

**보정 출처 분포 (461장)**:
- MANUAL: 169 (사용자 수동 검수)
- AUTO_ACCEPT: 158 (JP/EN raw percentile 양쪽 ≥0.85 또는 ≤0.70)
- SUPPORTER_DETECTED: 130 (DB super_type=TRAINER 자동 감지)
- SUPPORTER_DETECTED_FROM_MANUAL: 1 (사용자 MANUAL → TRAINER 자동 보정)
- POKEMON_V_RESTORED: 3 (DB corruption 복원 — 네오라이트 V/백솜모카 V)

---

## 7. 적용된 계수

```sql
-- price_snapshots SYSTEM row (loadRarityCoefficients()가 latest fetch)
INSERT INTO price_snapshots (price_snapshot_id, card_id, source, price, card_status, traded_at, collected_at)
VALUES
  (uuid, 'ko_coef_jp_SWSH_SR_SUPPORTER', 'SYSTEM', 2765, 'RAW', now(), now()),  -- 0.2765
  (uuid, 'ko_coef_en_SWSH_SR_SUPPORTER', 'SYSTEM', 8945, 'RAW', now(), now());  -- 0.8945
```

- **저장 형식**: `price = coef × 10000` (정수)
- **loadRarityCoefficients()** 변환: `card_id.replace("ko_coef_", "")` → `jp_SWSH_SR_SUPPORTER` / `en_SWSH_SR_SUPPORTER` key
- **resolveCoeffDetail**에서 `sourceKey + "_" + marketSegmentKey` lookup
- **DISTINCT ON (card_id) + ORDER BY traded_at DESC** — 새 INSERT 자동 우선

**산출값 근거** (recalc.py 같은 패턴 dry-run):
- JP 33 obs / median 0.2765 / IQR fence 통과
- EN 29 obs / median 0.8945
- CARD coef 카드 제외 (`median_without_card_coef`) 기준
- `KO_MARKET_ADJUSTMENT × 1.12` 곱 안 함 (raw ratio 그대로 — KO 시장 가격에 이미 반영됨)

---

## 8. 검증 결과 (모두 통과)

| 검증 | 기대값 | 실제 결과 |
|---|---|---|
| 14일 backfill saved | 51,696 | ✅ 51,696 |
| 14일 backfill savedAudits | 51,696 | ✅ 51,696 (1:1) |
| backfill 소요 시간 | < 2분 | ✅ 59.8초 |
| 보스의 지령(비주기) 5/3~5/17 scope | 전부 MARKET_SEGMENT | ✅ 15일 모두 `en_SWSH_SR_SUPPORTER` |
| 보스의 지령(비주기) 5/16→5/17 점프 | 평탄화 | ✅ 89,099 → 89,099 (0% 점프) |
| 카밀레의 반짝임 5/3~5/17 scope | 전부 CARD | ✅ 15일 모두 CARD scope 유지 |
| 카밀레의 반짝임 가격 | 자연 변동만 | ✅ 18,548 → 18,166 (-2%, raw 자연 변동) |
| 오늘 top-gainers | 0건 (raw 변동 없음) | ✅ 0건 |
| 오늘 top-losers | 0건 | ✅ 0건 |
| recent-gainers SUPPORTER 의심 카드 | 0건 | ✅ 0건 (보스의 지령 12.1%는 다른 card_id 진짜 변동) |
| 5/17 audit MARKET_SEGMENT 분포 | 108장 | ✅ 108장 |
| SUPPORTER 109장 ranking_eligible | 100% false | ✅ LOW_PRICE 78 + ANOMALY 30 + ZERO_CHANGE 1 (총 109) |
| POKEMON이 SUPPORTER segment에 잘못 분류 | 0 | ✅ 0 |
| backup 테이블 row 수 | 14~15일 데이터 | ✅ price_snapshots 55,405 / audit 55,404 |

**SWSH_SR_SUPPORTER 109장 세부 내역**:
- MARKET_SEGMENT 적용 대상: **108장** (JP 69 + EN 39)
- CARD coef 보호: **1장** (카밀레의 반짝임 — CARD scope 유지)
- 랭킹 노출: **0장** (전부 ranking_eligible=false — 가짜 급상승 차단)

**backup vs backfill row count 차이 설명**:
- `backfill saved 51,696`: **5/3 ~ 5/16** 과거 14일 재생성 대상만 포함 (offset 1~14)
- `backup 55,405 / 55,404`: **5/3 ~ 5/17** (오늘 refresh 데이터 포함, `traded_at >= CURRENT_DATE - INTERVAL '14 days'`)
- 차이 ≈ 3,709 = 오늘(5/17) refresh KO_ESTIMATED row 수와 일치

---

## 9. 생성/변경된 주요 테이블

### 신규 테이블
| 테이블 | 용도 |
|---|---|
| `ko_estimation_audit` | KO_ESTIMATED 산출 추적 (40+ columns) |
| `card_market_segment_overrides` | card_id → market_segment_key 매핑 (461장 SWSH SR/HR) |

### 기존 테이블 변경
| 테이블 | 변경 |
|---|---|
| `price_snapshots` | `ko_coef_jp/en_SWSH_SR_SUPPORTER` 2 SYSTEM row 추가 |

### 백업 테이블 (2026-05-17 생성)
| 테이블 | row count |
|---|---|
| `price_snapshots_backup_20260517_pre_swsh_segment` | 55,405 |
| `ko_estimation_audit_backup_20260517_pre_swsh_segment` | 55,404 |

### 신규 코드 파일
- `back/src/main/java/com/fury/back/domain/price/KoEstimationAudit.java`
- `back/src/main/java/com/fury/back/domain/price/KoEstimationAuditRepository.java`
- `back/src/main/java/com/fury/back/domain/price/AuditSource.java`
- `back/src/main/java/com/fury/back/domain/price/CardMarketSegmentOverride.java`
- `back/src/main/java/com/fury/back/domain/price/CardMarketSegmentOverrideRepository.java`
- `back/sql/card_market_segment_overrides.sql` (DDL + CHECK)
- `back/sql/cmso_import_20260517.sql` (461 INSERT 백업)
- `back/export/rarity_segment_check/*` (분석 CSV 12종 + HTML 검수 도구)

---

## 10. 데이터 수집 필요 항목 (P1~P5 우선순위)

**파일**: `back/export/rarity_segment_check/market_segment_price_collection_targets.csv` (352장)

| 우선순위 | segment | 카드 수 | 현재 obs | 목표 | 비고 |
|---|---|---|---|---|---|
| **P1** | SWSH_HR_SPECIAL_ART | 11 | 4 | 15+ | 11장 자체 적음 — 전체 수집 가능 |
| **P2** | SWSH_SR_SPECIAL_ART | 41 | 8 | 15+ | top 20장 권장 |
| P3 | SWSH_HR_RAINBOW | 77 | 10~11 | 15+ | top 30장 권장 |
| P4 | SWSH_HR_SUPPORTER | 71 | 1 | 10~15 | 1 obs는 outlier 위험 |
| P5 | SWSH_SR_FULLART | 152 | 0 | 15~20 | 영향 낮음 (저가 SR) |

### P1 SWSH_HR_SPECIAL_ART 11장 (전부)
블래키 VMAX · 글레이시아 VMAX · 님피아 VMAX · 리피아 VMAX · 레쿠쟈 VMAX · 뮤 VMAX · 연격 우라오스 VMAX · 일격 우라오스 VMAX · 흑마 버드렉스 VMAX · 백마 버드렉스 VMAX · 두랄루돈 VMAX

### P2 SWSH_SR_SPECIAL_ART top 우선 카드
기라티나 V · 루기아 V · 레쿠쟈 V · 망나뇽 V · 블래키 V · 리자몽 V · 마기라스 V · 에브이 V · 님피아 V · 프테라 V · 글레이시아 V · 리피아 V · 뮤 V · 괴력몬 V · 오리진 펄기아 V · 부스터 V · 샤미드 V · 제라오라 V · 돈크로우 V · 골루그 V

---

## 11. 한국 RAW 체결가 수집 기준

### ✅ 인정
- 네이버 카페 체결가
- 번개장터 거래완료
- 당근 거래완료
- 카드샵 판매완료
- 실제 매입/판매 내역

### ❌ 제외
- 판매중 호가
- PSA / BGS / CGC 감정가
- 미개봉 박스 / 팩
- 해외 가격 (eBay 등)
- 카드번호 확인 불가능한 거래
- 상태 훼손 심한 카드

### 수집 형식
```
카드명:
segment:
세트명:
카드번호:
한국 RAW 체결가:
거래일:
출처:
상태:
캡처 있음/없음:
비고:
```

**예시**:
```
카드명: 기라티나 V
segment: SWSH_SR_SPECIAL_ART
세트명: 로스트어비스
카드번호: 111/100
한국 RAW 체결가: 520,000원
거래일: 2026-05-xx
출처: 네이버 카페 체결
상태: RAW
캡처 있음
비고: PSA/미개봉 아님
```

---

## 12. 다음 작업 순서

1. **폰 앱 눈검증** (사용자 수동)
   - 보스의 지령(비주기) / 마리 / 카틀레야 14일 차트 자연스러움 확인
   - top-gainers / recent-gainers 화면 정상 노출 확인
2. **Codex 코드 리뷰 요청** (CLAUDE.md 원칙)
   - 범위: `GlobalPriceService` 신규/변경 부분, `CardRepository` 4개 ranking SQL, `KoEstimationAudit`/`CardMarketSegmentOverride` entity, DDL
3. **admin endpoint 보안** (deploy 전 필수)
   - `/api/prices/admin/dry-run-audit` dev/local 제한
   - `/api/prices/admin/refresh-ko-estimates` 인증 추가
   - SecurityConfig admin endpoint 보호
4. **P1/P2 한국 RAW 체결가 수집** (사용자 수동, 시간 소요 큼)
5. **수집 데이터 INSERT** → recalc dry-run 재실행
6. **충분한 segment만 coef INSERT** (obs ≥15 + JP/EN 양쪽 모두)
7. **14일 backfill 반복** → 차트 평탄화 확인 → 랭킹 재검증

---

## 13. 아직 하면 안 되는 것 (금지사항)

| 금지 | 사유 |
|---|---|
| **SWSH_SR_SPECIAL_ART 계수 즉시 적용** | obs 8건 부족 (15+ 필요) — 잘못 적용 시 41장 가격 왜곡 |
| **SWSH_HR_RAINBOW 계수 즉시 적용** | obs 10~11건 부족 — shrinkage 권장 |
| **SWSH_HR_SPECIAL_ART 계수 즉시 적용** | obs 4건 — 너무 부족, fallback 유지 |
| **SWSH_HR_SUPPORTER 계수 즉시 적용** | obs 1건 (스쿨보이 1장, currency='USD' corruption 의심) |
| **KO_ESTIMATED 가격 기반 segment 자동 분류** | **cyclic error** — 잘못된 KO 가격으로 잘못된 segment 만듦 |
| **판매중 호가 기반 계수 산출** | 실거래 아님 |
| **PSA/BGS/CGC 감정가로 계수 산출** | RAW와 가격 체계 다름 (보통 5~50배 차이) |
| **추가 segment 적용 후 backfill 안 하기** | 5/17만 튀고 14일 차트 부자연스러움 |
| **CARD coef 카드를 segment 평균에 포함** | CARD가 priority 우선이라 적용 안 됨에도 segment median 왜곡 |
| **백업 없이 14일 backfill force** | rollback 불가 |

---

## 14. 남은 기술 부채

### 🔴 deploy 전 필수
1. `/api/prices/admin/dry-run-audit` 운영 노출 차단 (dev/local profile 또는 admin 인증)
2. `/api/prices/admin/refresh-ko-estimates` 인증 (메모리 `project_must_before_deploy.md`)
3. SecurityConfig admin endpoint 보호
4. JWT secret / CORS 정리

### 🟡 단기 정리
5. `recalc_coefficients.py`에 `--mode market_segment` 정식 추가 (현재는 임시 python script `/tmp/market_segment_dryrun.py`)
6. `ko_price_coefficients` era 컬럼 dead code 정리 또는 활용
7. KREAM promo (`savePromoKoEstimatedFromKream`) audit 처리 누락 — 별도 audit 경로 또는 의도적 fallback 명시

### 🟢 중기 데이터 정리
8. DB super_type=TRAINER + card_type=포켓몬 element corruption SWSH 외 106장 (SM 33 / SV 20 / MEGA 5 / XY 4 / BW 1) cleanup migration
9. PSA10_FALLBACK 케이스 실데이터 0건 — 데이터 확보 후 검증
10. `NO_EVIDENCE` 14번째 reason 조건 미정의 — 사용자 결정 필요

### 🔵 장기 확장
11. SV / SM / MEGA / XY / BW 시대 market_segment 확장 (동일 흐름 반복)
12. recent-gainers `moveDate` UI 표시 (currentPrice ≠ moveDatePrice 명확화)
13. 신규 카드 추가 시 segment 자동 분류 로직

---

## 15. Rollback 방법

### 권장 순서 (가벼운 것부터)

**Level 1 — market_segment 계수만 비활성화 (가장 가벼움)**
```sql
-- ko_coef_jp/en_SWSH_SR_SUPPORTER 2 row만 백업 후 삭제
CREATE TABLE ko_coef_swsh_supporter_backup AS
SELECT * FROM price_snapshots
WHERE card_id IN ('ko_coef_jp_SWSH_SR_SUPPORTER', 'ko_coef_en_SWSH_SR_SUPPORTER')
  AND source = 'SYSTEM';

DELETE FROM price_snapshots
WHERE card_id IN ('ko_coef_jp_SWSH_SR_SUPPORTER', 'ko_coef_en_SWSH_SR_SUPPORTER')
  AND source = 'SYSTEM';
-- 이후 refresh → MARKET_SEGMENT lookup 실패 → 기존 RARITY/GLOBAL fallback
```

**Level 2 — 코드에서 MARKET_SEGMENT lookup 비활성화 (코드 revert)**
- `resolveCoeffDetail`에서 MARKET_SEGMENT 분기 주석 처리 또는 short-circuit
- 백엔드 재시작 → segment override 있어도 무시 → 기존 lookup만 사용
- 가장 안전한 일시적 disable 방법

**Level 3 — 14일 KO_ESTIMATED + audit 복구 (데이터 차원 rollback)**
```sql
-- 1. 현재 14일 KO_ESTIMATED 삭제 (FK CASCADE로 audit도 삭제)
DELETE FROM price_snapshots
WHERE source = 'KO_ESTIMATED'
  AND traded_at >= CURRENT_DATE - INTERVAL '14 days';

-- 2. backup에서 복구
INSERT INTO price_snapshots
SELECT * FROM price_snapshots_backup_20260517_pre_swsh_segment;

-- 3. audit 명시적 복구 (FK CASCADE로 이미 삭제됐을 수 있음)
INSERT INTO ko_estimation_audit
SELECT * FROM ko_estimation_audit_backup_20260517_pre_swsh_segment
ON CONFLICT (id) DO NOTHING;
```

**Level 4 — card_market_segment_overrides 비우기 (최후 수단)**
> ⚠️ **이건 461장 분류 결과 전체 손실** — 다시 분류하려면 manual 검수 + import 재수행.
> Level 1~3로 안 풀릴 때만 사용.

```sql
-- 백업 먼저
CREATE TABLE cmso_backup_full AS SELECT * FROM card_market_segment_overrides;
-- 그 다음 비우기
DELETE FROM card_market_segment_overrides;
```

**Level 5 — 신규 테이블 완전 제거 (nuclear option)**
> ⚠️ **코드도 rollback 필요** (Turn A~D 변경 revert). 사실상 새 환경으로 후퇴.

```sql
DROP TABLE IF EXISTS card_market_segment_overrides;
DROP TABLE IF EXISTS ko_estimation_audit;
```

### 절대 하지 말 것

- ❌ **`price_snapshots`에 dummy SYSTEM coef row 삽입으로 덮어쓰기**
  - `loadRarityCoefficients()`가 `DISTINCT ON (card_id) ORDER BY traded_at DESC`로 latest를 읽으므로 dummy row가 오히려 latest로 잡혀 더 위험
  - rollback은 **삭제 / 코드 비활성화 / backup 복구** 방식으로만 처리

### Rollback 후 검증 SQL
```sql
-- Level 1 검증 (coef row 삭제)
SELECT COUNT(*) FROM price_snapshots WHERE card_id LIKE 'ko_coef_%SWSH_SR_SUPPORTER%' AND source='SYSTEM';
-- 기대값: 0 (또는 backup row가 있으면 그 row만)

-- Level 3 검증 (14일 backfill 복구)
SELECT COUNT(*) FROM price_snapshots WHERE source='KO_ESTIMATED' AND traded_at >= CURRENT_DATE - INTERVAL '14 days';
-- 기대값: backup 55,405와 동일 (또는 ±오늘 refresh 차이)

-- 전체 MARKET_SEGMENT 사라짐 확인
SELECT coef_scope, COUNT(*) FROM ko_estimation_audit WHERE estimated_date=CURRENT_DATE GROUP BY coef_scope;
-- MARKET_SEGMENT 0건이면 rollback 성공
```

---

## 16. 앱 눈검증 카드 (배포 전 QA 체크리스트)

폰 앱에서 아래 5개만 확인하면 시세 변경이 정상 반영됐는지 빠르게 검증 가능.

| # | 카드 | 화면 | 기대 결과 |
|---|---|---|---|
| 1 | **보스의 지령(비주기)** SR | 상세 → 14일 KO 차트 | 5/3~5/17 평탄 (5/16→5/17 +38% 점프 없음, 86K~89K 자연 변동) |
| 2 | **마리** SR EN | 상세 → 14일 KO 차트 | EN 기반 상승분이 14일 전체에 자연스럽게 반영 (예: 40~50K 수준) |
| 3 | **카틀레야** SR EN | 상세 → 14일 KO 차트 | SUPPORTER 적용 확인 (generic SR보다 +38% 높은 가격대) |
| 4 | **카밀레의 반짝임** SR | 상세 → 14일 KO 차트 | CARD scope 보호 — 18K 수준 안정 (SUPPORTER 영향 받지 않음) |
| 5 | **급상승/급하락 화면** | 메인 → 시세 탭 | 계수 변경 카드(보스의 지령, 마리, 카틀레야 등) 노출 0 — 실제 시장 변동 카드만 노출 |

**검증 빠른 SQL** (DB 직접 확인용):
```sql
-- 보스의 지령(비주기) 14일 시계열
SELECT estimated_date, ko_price, coef_scope
FROM ko_estimation_audit
WHERE card_id='CRD_39A2F0B42FC5405188AA' AND estimated_date >= CURRENT_DATE - 14
ORDER BY estimated_date;
-- 기대: 모두 MARKET_SEGMENT scope, 86K~89K 자연 변동

-- 카밀레의 반짝임 14일
SELECT estimated_date, ko_price, coef_scope
FROM ko_estimation_audit
WHERE card_id='CRD_B6F05ABED7AE47BAAD56' AND estimated_date >= CURRENT_DATE - 14
ORDER BY estimated_date;
-- 기대: 모두 CARD scope, 18K~19K 안정
```

---

## 17. 사용자 인수인계 핵심 (2026-05-18 추가)

### 사용자가 다음에 할 일 (정확한 흐름)

```
1. P1 SWSH_HR_SPECIAL_ART 11장 한국 RAW 체결가 수집
2. 사용자는 거래 데이터만 전달 (CSV 또는 메시지)
3. 이후 작업 (자동 X — 검증 후 적용):
   ├─ DB INSERT (NAVER_CAFE_OLD, validation_status=VALID)
   ├─ dry-run으로 obs / median / outlier 검증
   ├─ obs ≥ 15 + JP/EN 양쪽 안정 + outlier 없음 확인
   ├─ 안정성 OK 시 segment coef INSERT (price_snapshots SYSTEM)
   ├─ 14일 force backfill (백업 후)
   └─ 검증 (시계열 평탄화 + 랭킹 오염 없음)
```

**핵심**: 거래 INSERT만으로 segment 계수가 자동 적용되지 않음.
반드시 dry-run 검증 후 수동 INSERT + backfill 필요.

### 수집 안정성 기준

```
P1 11장 거래가 수집 후 dry-run에서:
- JP source obs ≥ 15
- EN source obs ≥ 15
- IQR fence 통과 후 median 안정 (p25/p75 범위 합리적)
- outlier 1건이 median 흔들면 SHRINKAGE 적용

→ 모두 충족 시 SWSH_HR_SPECIAL_ART coef 적용 후보로 올림
→ 한 조건이라도 부족하면 추가 수집 또는 FALLBACK 유지
```

### 데이터 수집 출처 신뢰 순위

| 순위 | 출처 | 신뢰도 | 비고 |
|---|---|---|---|
| 1 | 네이버 카페 체결 + 캡처 | 매우 높음 | 가장 신뢰 |
| 2 | 번개장터 거래완료 | 높음 | 거래 가격 정확 확인 |
| 3 | 당근 거래완료 | 높음 | |
| 4 | 카드샵 판매완료 | 중간 | 할인/프리미엄 가능 |
| 5 | 개인 매입/판매 내역 | 가능 | 캡처 권장 |

### 수집 효율 팁

- 한 카드에 5건 몰리는 것보다 **다른 카드 5장에 1건씩** 분산이 더 안정
- 비싼 카드 우선 (median 영향 큼) — 블래키 VMAX / 레쿠쟈 VMAX 등
- 거래일은 가급적 최근 60일 이내 (recalc.py 60일 window)

### 사용자 액션 = 1개

> **P1 11장 카드 거래가 모아서 메시지로 전달.** 그 외는 다음 세션에서 처리.

### 안 해도 되는 것

- 코드 수정 / 백엔드 재시작 (불필요)
- DB 직접 INSERT (검증 누락 위험)
- 매일 시세 변동 모니터링 (audit가 자동 차단)
- segment 적용 결정 (dry-run 검증 후 같이 결정)

---

## 참고 — 작업 기간 / 변경 규모

- **작업 기간**: 2026-05-15 ~ 2026-05-17 (3일)
- **코드 변경**: ~1,500줄 (GlobalPriceService 750 + Repository 300 + Entity 200 + Controller/DTO 250)
- **신규 SQL migration**: 3종 (audit, market_segment, import)
- **분석 CSV**: 12종 (`back/export/rarity_segment_check/`)
- **HTML 검수 도구**: 1종 (`swsh_sr_hr_review.html` 107KB)
- **Backup 테이블**: 2종 (110,809 row 보존)

## 참고 — 핵심 메모리 / 정책 문서

- `docs/PRICE.md` — 시세 시스템 전반
- `docs/PRICE_POLICY_2026_05_16.md` — Phase 0+X freeze 정책 (단일 진실원)
- `~/.claude/projects/-Users-fury-pokemon-card-app/memory/` — 사용자 auto-memory
  - `project_ko_price_system.md` — KO 가격 시스템 진행 상태
  - `project_must_before_deploy.md` — deploy 전 필수 항목
  - `feedback_codex_review.md` — Codex 리뷰 원칙

---

> **최종 한 줄**:
> KO_ESTIMATED 산출은 audit 기반으로 추적 가능해졌고, 랭킹은 "실제 시장 변동"만 노출하는 구조로 완성됐다.
> 추가 정확도는 한국 RAW 체결가가 더 모이면 자동으로 개선되는 흐름.
