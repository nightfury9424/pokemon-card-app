# v8 — SNKRDUNK catalog 완료 후 로드맵 (2026-06-20)

## 현재 위치
- JP 트랙: SNKRDUNK `/v1/apparels/{id}` 전수 스캔 ~53% (detail만, sales 아직 X). catalog=포켓몬 싱글 ~35k+.
- KO 트랙: NAVER cardmvk **v8 미사용 확정**(등급/일판/경매 오염). KO는 당근/번장 한글판 RAW로 별도.
- 도구 다 됨: `snkrdunk_collect.py`(scan+match-and-collect), scanner `/identify`, evidence 스키마, v8 정책.

## ━━ catalog 다 모이면 (단계별) ━━

### 1. 매칭: snkrdunk catalog → 우리 card_id  ★다음 1순위
- 입력: `snkrdunk_apparel_catalog_scanned.csv`(~35k) + 우리 카드 4,225(scanner/data/cards)
- 방법: 각 snkrdunk 공식아트 → scanner `/identify` → top1 card_id(score≥0.75) **AND** 세트/번호/레어도 크로스체크 → MATCH_HIGH
- ★비용: 35k 전수 /identify는 비쌈(이미지다운+추론) → **레어도 필터(SR+만, 커먼 skip)** + 우리 659 타깃 우선 → ~1만으로 축소
- 산출: `snkrdunk_to_pokefolio_match_candidates.csv` (apparel_id→card_id, MATCH_HIGH/OUT_OF_SCOPE)
- 도구: `snkrdunk_collect.py --match-and-collect` (이미 만듦)

### 2. SOLD 수집: MATCH_HIGH 카드만
- MATCH_HIGH apparel만 → `/sales-history` → **A·PSA9·PSA10만**, 최근 60일
- card별 ladder(A median/PSA9/PSA10) + LADDER_OK/RAW_OVER_PSA10 sanity
- 산출: `snkrdunk_evidence_mapped.csv` (우리 card_id → JP SOLD ladder) = **JP evidence (2순위 소스)**

### 3. KO ground truth 수집 (별도 트랙, 1순위 소스)
- NAVER 제외. **당근/번장/앱거래의 한글판 RAW 단품 체결**.
- KO 7요건 게이트: ①한글판 ②단품 ③RAW ④카탈로그존재 ⑤매핑확정 ⑥체결 ⑦이미지.
- 기존 수집분 있으면 그것부터, 없으면 새로.

### 4. KO/JP 계수 캘리브레이션
- KO체결 + SNKRDUNK A급 **둘 다 있는 카드**로 → 실측 KO/JP 비율 (rarity/era별)
- SNKRDUNK만 있는 카드에 그 비율 적용 → KO 추정
- (지금까지 이 계수가 추측이라 사고남 — 이게 "예상가→실측" 핵심)

### 5. v8 decision 알고리즘 (KO+JP 합치는 단계)
- 카드별: ①KO체결 있으면 KO직접가(HIGH) → ②없으면 SNKRDUNK A급×계수 → ③Scrydex fallback → 다없으면 검수중
- sanity: ladder + 교차밴드(|KO vs JP×계수|≤25%=일치, >25%=USER_COMP_REQUIRED)
- confidence: HIGH(KO체결)/MED(SNKRDUNK)/LOW(Scrydex)/검수중
- ★MANUAL_ANCHOR>FLOOR>FROZEN>v8 우선순위. PSA9 tolerance band.

### 6. 구현 (승인 후, gated)
- `price_evidence_external` 테이블(설계됨, 마이그 승인후) + v8_decide(Java add-time/preview + Python nightly 단일함수) + 앱 "검수중" 라벨
- **v6 안정화 후 + 승인 후 + 데이터 신뢰 확인 후.** 며칠 규모. 자동 가격반영은 그 다음.

## 합치는 시점 = 5번. 그 전엔 JP(SNKRDUNK)·KO(당근/번장) 따로.
## 금지: prod write·자동가격·신규59·미등록수집·NAVER사용·v6/live.
