# SNK A vs scrydex JP — 비교 분석 (2026-06-29)

> **분석 전용. prod write 0 · 가격 반영 0 · 배포 0.** 여기서 SNK 작업 STOP → Android 준비로 전환.
> 이 데이터의 매핑은 **working / high-confidence mapping**이며 **prod 반영용 confirmed mapping 아님.**

## 0. 실행 컨텍스트 (정직)
- **SNK API pull + 비교 스크립트 = 로컬 Mac** 실행 (`/Users/fury/...`, 운영서버 아님).
- **prod(`pokemon_card_db`) = read-only만**: `docker ps` / `psql -l` / `SELECT`(scrydex JP sanity·export·환율). **INSERT/UPDATE/DELETE/CREATE/DROP/배포/cron = 0.**
- ⚠️ **절차 메모**: prod read-only도 SELECT 쿼리 보여주고 **승인 받은 뒤** 실행했어야 함(같은 흐름에서 바로 실행함). 다음부터 운영 DB 접근은 **승인 먼저**.

## 1. SNK 수집 정책 (확정)
| 옵션 | salesChartOptionId | 역할 |
|---|---|---|
| A | 18 | **JP raw 주력** (oneMonth → 부족시 threeMonths) |
| PSA10 | 22 | graded ladder 참고만 |
| PSA9 | 23 | graded ladder 참고만 |
| usedMinPrice | (detail) | **현재 중고 최저 호가(ASK)** 보조 — 실거래 아님 |
| all | -1 | **미수집/미사용** (등급 슬랩 혼입 → raw 오염) |

검증: 뮤 EX = A raw 무거래인데 all(-1) median ¥897,500(PSA10 혼입). A 분리로 차단.

## 2. 최종 숫자 (완전한 3,314 기준)
```
working mapping total        : 3,314
A points 존재 전체            : 1,200
MAPPING_REVIEW 제외 A usable  : 1,028   ← A_1M_OK 689 + A_3M_FALLBACK 339
A no points                  : 2,114   ← SCRYDEX_ONLY 1,953 + NO_DATA 161
MAPPING_REVIEW(극단 ratio)    : 172     ← 적용 전 검수 필요
PSA10 points 있음            : 1,936  (ladder 참고)
PSA9 points 있음             : 1,020  (ladder 참고)
usedMinPrice>0              : 2,757  (ASK 보조)
```

## 3. scrydex vs SNK A 발견 (단순 인플레 ❌ — bidirectional)
- 비교가능(둘다 값) **1,095**, 그중 견고(SNK A n≥5) **472**.
- ratio(scrydex/SNK A) 중앙값 = **0.71** 전체 / **0.81** 견고.
- **AR/SAR** 중앙값 **0.97**(≈동일, 꼬리에 scrydex 2~4배 과대: 돌살이·파라스 등 커먼 AR).
- **non-AR** 중앙값 **0.57**(scrydex 낮음 = ①싼 카드 SNK ¥1,000 floor > scrydex ②체이스 EX 프로모 scrydex 과소).
- scrydex 2배+ 높음 34장(SNK 대체 시 ↓) / 50%- 낮음 352장(↑).

## 4. 결론 — JP 소스 정책
```
JP raw = SNK A (n≥5 견고할 때 주력, 472장 실측 upgrade)
         SNK A thin(n<5)은 참고 + scrydex 교차검증
SNK A 없음(2,114, 64%) = scrydex JP fallback 유지   ← 전면 대체 금지
PSA10/PSA9 = ladder 참고만 (raw 미혼입)
usedMinPrice = ASK 보조만 (실거래 호칭 금지)
all(-1) = 미사용
EN = scrydex 유지
매핑의심 172장 = 적용 전 검수
```
**SNK A는 품질↑·커버리지↓.** 전면 대체 아님 → **A 거래 충분한 카드부터 부분 적용** 후보.

## 5. 산출물 (전부 분석용·로컬)
| 파일 | 내용 |
|---|---|
| `python/price_v8/snkrdunk_working_mapping.csv` | working/high-confidence 매핑 3,314 (★confirmed 아님) |
| `python/price_v8/snk_price_full.csv` | SNK 전수 pull (A/PSA10/PSA9 1m+3m + detail) |
| `python/price_v8/scrydex_jp_prod.csv` | prod read-only export (scrydex JP latest+30d median) |
| `python/price_v8/snk_vs_scrydex_jp_compare.csv` | 비교표 3,314 × 32컬럼 |
| `python/price_v8/snk_price_pull_full.py` · `build_snk_vs_scrydex.py` | 스크립트 |
| prod 쿼리 | `SELECT ... price_snapshots WHERE source='SCRYDEX_JP' AND card_status='RAW' GROUP BY card_id` (read-only) |

## 6. 다음 (하지 말 것 / 할 것)
- ❌ 전환 시뮬레이션·가격 반영·DB 적용·추가 크롤링·프로모/카드 추가
- ✅ 산출물 백업 → **Android 준비로 전환** (진입점 `docs/ANDROID_RELEASE_HANDOFF_20260628.md`)
- (재개 시) 매핑의심 172 검수 → 견고 472 부분 전환 시뮬 → ¥1,000 floor 정책
