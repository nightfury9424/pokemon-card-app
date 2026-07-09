# Grail/체이스 KO 예상가 과소 — 진단 완료 · 교정 대기 (2026-06-30)

> **한 줄**: 앱 KO 예상가가 grail/체이스에서 수십~수백 배 과소. 원인 = ①spread 규칙이 JP 있는데 EN 선택 ②v6 계수가 grail을 죽임 ③프로모 scrydex raw가 SNK보다 낮음. **진단·증거·검수도구 완성. prod write 0. 교정(v8 backend)은 별도·백업+승인 후.**

발단: 사용자가 레시라무 SR 055/053 앱 KO **₩17,030**(일본 실거래 ₩1M+) 포착.

---

## 1. 근본 원인 (prod 하드데이터로 확정)

KO 예상가 = `selected_raw × 계수` (v6). 세 갈래로 망가짐:

1. **선택 버그 (spread→EN)**: JP RAW이 있는데도 `spread>threshold→EN` 규칙이 더 싼 EN을 고름.
   - EN 선택 1,742장 중 **86%(1,498)가 유효 JP RAW 보유** = "JP 없어서"가 아님.
   - 릴리에 065/060: JP RAW ₩7,125,000(fresh) 있는데 EN $48.99(₩75k) 선택.
2. **계수 버그**: `KO = raw × 계수`, 계수가 grail에 0.078~0.34. **JP를 골라도** `JP×0.078` 때려 과소.
3. **프로모(PROMO_DIRECT)**: 계수 미적용·raw 그대로 트랙인데 **scrydex JP raw 자체가 SNK 실거래보다 낮음** → 과소. (프로모에 계수 곱하면 안 됨.)

= 메모리 v8 anchor 설계결함("¥1.2M이 $76", "릴리에류 grail JP>>EN=과소") 그대로. prod audit `is_anomaly=false` = 사각지대.

---

## 2. prod 진실원 (read-only, `pokemon_card_db`)

- **`ko_estimation_audit`** = KO 산출 진실원. `card_id · ko_price · selected_source(EN 1742/JP 2114/PROMO_DIRECT 30) · coef_value · selected_raw_price_krw · is_anomaly`.
- **`price_snapshots`** = scrydex JP/EN RAW + JP GRADED(PSA9/10). `price` 컬럼 = KRW 환산값. `validation_status='VALID'`.
- **`ko_price_coefficients`** = 계수 (coef_type **EN/JP/BLEND**, scope CARD/RARITY, era/rarity). RARITY JP계수: SR 0.388629 · AR 0.535789 · SAR 0.376892 · UR 0.491811 · HR 0.432255 · PR 0.085544. CARD-scope는 29장만.
- `cards` 테이블엔 가격 컬럼 없음(refs/is_visible만).
- ssh: `-i ~/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120` → `docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db`. **read-only도 쿼리 보여주고 승인 먼저.**

---

## 3. 방법론 (★GPT 검토 반영, 산출로직 분리)

- **현재KO** = audit `ko_price` 실제값 (재구성 금지).
- **가격모드(pricing_mode)**: `COEF`=일반(raw×JP계수) / `RAW_DIRECT`=프로모(**raw 그대로, 계수 미적용**).
- **JP시나리오** = COEF면 `JP_raw × JP계수`, RAW_DIRECT면 `JP_raw 그대로`. JP_raw/계수 없으면 **NA**(snk 대용 금지).
- **SNK시나리오** = 동일 로직 with `SNK_raw`. 없으면 NA.
- **선택버그_raw(raw레벨) ≠ 과소_JP/과소_SNK(최종KO레벨)** 완전 분리.
- **actionable = 과소_JP 또는 과소_SNK** (= 분류 UNDERPRICED).
- **ladder = 내림차순 순서 표기만**(정상판정 안 함). ★grail/체이스는 **PSA10 > RAW > PSA9 정상**(raw가 PSA9보다 비쌈=grading 기대), 일반카드는 PSA10 > PSA9 > RAW. 카드군별로 다름.
- 비교는 **RAW-to-RAW**(EN raw vs JP raw) + 시나리오는 **같은 v6 모델, 소스만 교체**. KO를 JP raw에 직접 대지 말 것.
- `NA`=데이터/계수 없음(0 아님). `0`은 실제 0만.

---

## 4. 결과 (검토대상 726 = 대체 raw > 선택 raw ×1.5)

| 분류 | 수 | 의미 |
|---|--:|---|
| **UNDERPRICED** | **630** | 과소_JP 또는 과소_SNK True — **actionable 후보** |
| COEF_MISSING | 70 | 고가인데 JP계수 없어 계산불가 (계수 필요) |
| SELECTION_ONLY | 19 | raw EN오선택이나 최종KO 과소 아님 |
| REVIEW | 7 | 대체 raw 높으나 과소 아님 |

**대표 (현재KO → 시나리오):**
- 릴리에 SR 065/060 (EN): ₩12,646 → JP ₩2,768,982 / SNK ₩1,735,228
- 아세로라 SR 056/049 (EN): ₩13,051 → JP ₩2,215,185 (SNK NA)
- 뮤츠&뮤 GX 098/094 (JP선택인데도): ₩49,130 → JP ₩243,536 / **SNK ₩1,181,432** (scrydex JP raw가 SNK의 1/4.8=scrydex도 과소)
- 흉내내기 피카츄 PR 407/SM-P (프로모): ₩343,833 → SNK ₩705,366 (raw 그대로, 계수 미적용)

---

## 5. 산출물 (`python/price_v8/snk_pipeline/`)

| 파일 | 역할 |
|---|---|
| `grail_underpriced_detector.py` | 1차 디텍터 (SNK확인 130장) |
| `grail_evidence.py` | ★증거 산출 코어 (로직 분리판) → `out/grail_evidence.csv` |
| `grail_table.py` | 검증용 표 → `~/Downloads/grail_table_20260630.{md,csv}` (GPT 검산용) |
| `grail_review.html` + `review_server.py /grail` | 이미지 검수 화면 (`http://127.0.0.1:8788/grail`) |
| `prod_ko_audit_latest.csv` · `prod_raw_evidence.csv` · `prod_coefficients.csv` | prod read-only 추출본 |

검수화면: category 필터(UNDERPRICED 기본) · 티어비교(scrydex vs SNK) · 경우의 수 3개 · 이미지.

---

## 6. 다음 (미실행 · 재개 시)

1. **정답 KO 채택 규칙 결정**: SNK 실거래 있으면 SNK 우선 / 없으면 scrydex JP / 프로모는 raw 그대로 / 사람 최종검수. (KO=한국판이라 JP 대비 할인 여부도 카드별 판단.)
2. **COEF_MISSING 70장**: 계수 없는 rarity(K, SM-P 등) 처리.
3. **근본 수정 = v8 backend** (prod write, **백업+승인 후 별도 세션**):
   - spread 선택규칙 → JP-sanity-first (JP≫EN grail이면 JP 앵커, EN 금지)
   - grail/체이스 계수 → floor table 또는 SNK 실거래 기반
   - 프로모 scrydex raw 검증
4. 현재 **prod write/apply 0**. 검수·승인 트랙(승인/거절 버튼)은 아직 미구현.

★ 진입점 메모리: `project_grail_underpriced_20260630`. SNK 파이프라인 본체: `docs/SNK_PRICE_PIPELINE_DESIGN.md` / `project_snk_price_pipeline_20260629`.
