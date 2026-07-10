# 오리파 STEP 2 — 번호 오리파 뽑기 + 결과 리빌 (확정 스펙 / 진실원)

> **이 문서가 STEP 2 구현의 유일한 진실원이다.** 2026-07-08 사용자+GPT 확정.
> **2026-07-10 개정**: 개봉 확정 후 "결과 리빌" 도입 + GPT 리뷰 BLOCKER 4건 반영(재개정). 세션이 바뀌어도 이 문서 기준으로만 구현/판단한다.

## 🔄 개정 요지 (2026-07-10) — 리빌 도입
기존 STEP 2는 개봉 완료(82%) 직후 **바로 결과 시트**로 직행 → "결제 결과 화면 넘겨보는 느낌"이라 손맛 없음. 이를 **개봉 확정 후 결과 리빌**로 교체한다. 핵심 원칙 2가지:
1. **개봉 전(추출+peel)은 결과와 완전 무관하게 동일** — §6 금지 규칙 그대로 유지(사전 전조·차등 봉인·파티클·잭팟 없음). 유저는 **블라인드로 결제·개봉을 커밋**한다.
2. **개봉 확정 후에만** 상품 메타데이터를 순차 공개하는 리빌 연출을 허용한다. 이미 결과가 확정·기록된 뒤라 "유도"가 아니라 "연출"이다. 단, 개봉 전후 분리가 사행성을 **해결**하는 건 아니며 강도는 정책에 따라 조절·비활성 가능해야 한다(§B 참고).

**번호 오리파 = 확정형 히어로 리빌 / 봉인형 오리파(향후) = 추측형 FIFA 리빌.** 시각 엔진(`revealing` 상태머신·렌더러·`RevealConfig`)은 **공용**, `RevealProfile`만 분리한다. 번호 오리파는 상품이 뽑기 전부터 공개돼 있으므로(§1·§9) "무엇이 나왔을까" 가짜 추측을 하지 않고, **선택한 번호의 상품이 내 것이 되는 확정 카타르시스**를 연출한다.

## ⛔ 사용 금지 (과거 모델 재오염 방지)
과거 웹 prototype(`oripa_demo/reveal.html`, `oripa_number.html`)과 초기 메모리의 아래 모델은 **개봉 전(추출·peel) 구간 구현 근거로 사용 금지**:
- 100칸 봉인물 **직접 선택 그리드** (→ 자동 추출로 대체)
- **개봉 전** 티어/JACKPOT/등급별 봉인물 차등 연출
- **개봉 전** 암전/파티클/폭죽/룰렛/셔플게임/빛한줄
- **개봉 전** 결과에 따른 봉인물 색/외형 변화, 결과 사전 전조
> ※ 위 효과 자체가 영구 금지는 아님 — **개봉 확정 후 `revealing` 구간에서는 프로파일/강도에 따라 허용**(§B). 금지는 오직 "개봉 전에 결과를 암시/차등하는 것".

## 범위
- **번호 오리파** 뽑기 + **확정형 리빌**까지 구현. 상품 봉인 오리파(sealed, 추측형 리빌)는 이번 범위 제외 → 기존 "준비 중" mock 유지(단, 리빌 엔진은 봉인형 재사용 가능하게 설계).
- 백엔드/API/DB/PG/포인트원장/실제추첨/영속화 **전부 금지.** Flutter **in-memory session mock** UX 검증. (RevealDescriptor는 mock 클라 파생하되 구조는 미래 서버 발급형과 동일 — §B.)
- 개봉 대체 접근성(a11y) 경로는 이번 범위 제외 → §15 부채 기록만. (단, `reduceMotion`(접근성)·`effectsQuality`(저사양)는 리빌에 포함 — §B-4.)

---

## 1. 진입 (오리파 상세)
- 기존 번호 오리파 상세의 **상품판 유지**. 유저는 뽑기 전 번호별 남은 상품/획득된 빈자리를 본다. (→ 번호 오리파는 상품 사전공개 구조. 리빌은 확정형.)
- 하단 CTA `[1구 뽑기 · 50,000 P]` 탭 → 즉시 뽑지 말고 **확인 바텀시트**.

## 2. 확인 바텀시트 (오터치/오버셀 가드)
```
1구를 뽑을까요?
사용 포인트    50,000 P
현재 포인트   125,000 P
뽑은 후 잔액   75,000 P
"뽑기를 시작하면 취소할 수 없습니다."
[취소]   [1구 뽑기]
```
- `[1구 뽑기]` 누른 **그 시점(commit)에**: draw 번호 확정 + 포인트 차감 + drawCursor 이동 + 상품(prize)·RevealDescriptor 확정·기록 + `activeDraw`(COMMITTED) 생성 (§11).
- ★**`[1구 뽑기]`는 첫 탭 직후 즉시 비활성화**(이중 차감 방지).
- 결과는 **결정론적**(난수 아님). **애니메이션 도중 결과 결정/변경 금지.**

## 3. draw 시퀀스 & 초기 상태 (결정론)
- 초기 획득번호(taken) = **흩뿌린 고정 37개 set** (STEP 1의 `n<=sold` 연속식 폐기):
  ```
  {1,3,7,11,14,18,20,22,24,26,29,31,33,35,37,39,41,43,45,48,
   50,54,56,58,60,62,64,67,70,72,75,78,81,84,87,91,96}
  ```
  → 시작 = 획득 37 / 남은 63. 47·9·52 는 미획득.
- draw = **1~100 고정 full permutation**, 선두 반드시 `47 → 9 → 52`, 이후 나머지 번호. cursor가 순회하며 **이미 taken이면 skip**, 다음 미획득 번호 확정.
- 앱 재시작 시 초기 taken/커서로 **reset**. 난수 0.
- 남은 63개 전부 소진 시 **"매진"** (`남은 0구`, CTA disabled). **"데모 종료" 문구 금지.**

## 4. 번호 → 상품 (모든 번호가 실 상품)
- **generic "상품" placeholder 금지.** 100번 전부 실제 `OripaPrize`를 가진다.
- 8개 내외 mock 상품 catalog + 여러 번호가 **같은 상품 반복 매핑**(사장님이 수량 넣듯). deterministic.
- 최소 고정: `47=리자몽 ex SAR/280,000P`, `9=피카츄 계열/45,000P`, `52=뮤 ex/18,000P`. 나머지는 catalog 상품에 고정 매핑.

## 5. 상품 데이터 모델 (`OripaPrize`) — 카드 도메인과 완전 분리 (B 반영 / BLOCKER3 수정)
- **오리파 상품 = 매장 사장님이 직접 등록/업로드하는 물건.** 카드 마스터·CDN·`card_id`·시세/예상가·Scrydex/SNK/naver **전부 무관.** 플랫폼은 가치 심사자가 아님(교환P=사장님 결정).
- 리빌 단서(rarity/grade/set 등)는 카드 DB가 아니라 **사장님이 등록 시 입력하는 판매 표현 속성**. **`OripaPrize`는 `sealed` 타입** — 상품 종류별 서브타입이 필수 필드를 **구조적으로 보장**(nullable/optional·`null 고정` 같은 모순 없음, 고정 비트 불변식 §B-6.5). 리빌 프로파일·clue는 **타입 패턴 매칭**으로 결정.
```dart
sealed class OripaPrize {
  final String id;
  final String displayName;   // ★최종 상품명 단일 진실원 (= NAME 단서. "블래키 ex")
  final ImageRef imageRef;    // asset(현 mock) | network(미래 사장님 S3). card CDN/cardId 아님
  final int exchangePoints;
}
// RAW/GRADED = 타입으로 구분 → condition 필드 자체가 없음 (모순 조합 원천 불가)
final class RawCardPrize extends OripaPrize {      // → NUMBERED_CONFIRM_RAW / SEALED_MYSTERY_RAW
  final RarityCode rarityCode;      // 필수 (enum)
  final String     setDisplayName;  // 필수 (display 문구)
}
final class GradedCardPrize extends OripaPrize {   // → NUMBERED_CONFIRM_GRADED / SEALED_MYSTERY_GRADED
  final GradingCompany gradingCompany;  // enum PSA | BRG (OTHER 없음)
  final String         gradeValue;      // "10" 등, 정규화 입력·display
  final RarityCode     rarityCode;
  final String         setDisplayName;
}
final class SealedPackPrize extends OripaPrize {}  // → PACK_CONFIRM (카드 단서 필드 없음)
final class GoodsPrize      extends OripaPrize {}  // → GOODS_CONFIRM (카드 단서 필드 없음)
```
- **필수 필드는 서브타입 생성자가 강제** → 누락 시 생성 불가 = 파트너센터 "판매 시작 불가"와 정합. 카드 단서 필드는 서브타입에만 존재(공통 모델에 nullable 필드 없음 → `?`/`null 고정` 모순 소멸).
- **`condition` 없음** — RAW/GRADED는 **타입**으로 구분(불가능 조합 원천 차단).
- **`characterDisplayName` 없음** — 최종 상품명 = `displayName` 단일.
- **`GradingCompany` enum = `PSA | BRG`만** — 전역 규칙 "PSA·BRG만(CGC·BGS 금지)" 일치. `OTHER` 없음. (`GradingCompany`·`RarityCode`는 enum으로 정규화, 자유텍스트 `SAR/sar/사르` 혼입 방지.)
- **리빌 프로파일 결정 = `switch(prize)` 타입 패턴 매칭**(§B-2) — 안전하게 exhaustive.
- **연출 강도(intensity)는 OripaPrize에 두지 않는다** → §B-3의 `RevealPolicy`가 발급. 상품 사실 ≠ 표현 정책.
- STEP 2 mock 이미지 = 오리파 전용 local asset. 미래: 파트너센터 사장님 업로드 S3로 교체. 런타임 card DB/API 연결 금지.
- ⚠️ **폐기된 오판**: 카드 CDN `{cardCdnBase}/jp/{CRD_id}.png` 사용 + card master 조사 = 오리파를 카드 도메인에 잘못 연결. 다시 하지 말 것.

## 6. 뽑기 화면 (풀스크린)
- 확정 후 **ShellRoute 밖 새 route** `/oripa/draw/:oripaId`(바텀탭 없음).
- 결과 선택(보관/교환) 전까지 **일반 뒤로가기 차단**(PopScope). 뒤로가기 시 안내: "뽑기가 진행 중입니다. 결과를 확인한 뒤 이동할 수 있습니다."
- 상단엔 `남은 N구`만 작게.

## 7. 봉인물 자동 추출 (0.8~1.0s) — 개봉 전(결과 무관 동일)
- **100칸 그리드 금지.** 화면 중앙에 동일한 봉인물 **8~12장이 실제 카드 더미처럼 겹침**.
- 모션: 더미 살짝 눌림 → 위쪽 몇 장 미세하게 어긋남 → 봉인물 한 장이 앞으로 미끄러져 나옴 → 중앙에 놓임. (직원이 덱에서 꺼내주는 느낌)
- 룰렛/셔플/티어/잭팟/파티클/암전 금지. **스킵 버튼 없음.** **결과와 무관하게 모든 봉인물 외형·추출 모션 동일.**

## 8. 덮개 까기 → 번호 공개 (핵심 손맛) — 개봉 전(결과 무관 동일)
- 봉인물 = 포개진 카드 2장: 위=덮개 카드 / 아래=일반 RR 카드 + 흰 번호 스티커.
- 유저가 **위 덮개 카드 전체를 잡고 아래로 직접 드래그.** 세로가 기본, 손가락 좌우 이동에 따라 덮개 **-1.2°~+1.2° 미세 회전**.
- **진행 규칙 (스프링백 폐기):**
  - **아래로 단조 진행.** `progress = max(progress, calculated)`.
  - release 시 `progress < 5%` → 원위치(실수터치). `progress ≥ 5%` → **현재 위치 유지**, 다시 잡아 이어서 깐다.
  - ⛔ 스프링백(30% 못 넘기면 처음으로) 금지. "조금 내리고 멈추고 다시 잡고" 손맛이 핵심.
- **노출 순서 (진행률 기준):**
  | 진행률 | 노출 |
  |---|---|
  | 0~20% | 아래 RR 카드 윗부분 |
  | 20~45% | 흰 번호 스티커 가장자리 |
  | 45~60% | 숫자 일부 (예 "4…") |
  | 60%↑ | 번호 전체 확인 (예 "47") |
  | 82%↑ | 덮개 카드가 아래로 빠지며 **번호 완전 공개** → `revealing` 진입 대기 |
- **햅틱:** 60%(번호 전체) `lightImpact` 1회, 82%(완전 공개) `mediumImpact` 1회. **래치(중복 방지). 결과별 차등 없음.**
- **82% 이후**: 번호(예 47)만 확정 공개된 상태. **아직 상품 리빌 아님.** 약 0.8s 유지 후 하단 `[N번 상품 확인하기]` CTA → **유저가 직접 탭하면 §B(`revealing`) 진입.**

---

## B. 결과 리빌 (`revealing`) — 개봉 확정 후 (신설 2026-07-10)

### B-1. 상태머신
```
extracting → peeling → (번호 확인·CTA 탭) → revealing → revealed → resultActions
```
- `extracting`/`peeling`: **개봉 전.** §6~§8 금지 규칙 전부 유효(결과 무관 동일).
- `revealing`: **개봉 확정 후.** 상품 메타데이터 단서를 비트 단위로 순차 공개. 번호 오리파=확정형, 봉인형=추측형(프로파일로 분기).
- `revealed`: 상품 카드/슬랩 **풀스크린 히어로**, 최소 0.5~0.8s 유지(감상).
- `resultActions`: §10 보관/교환/다시 뽑기.
> ※ 기존 `_Phase{extracting, peeling, revealed}` → `revealing` 삽입. `revealed`가 결과창 직행하던 빈 구간이 리빌의 자리.
> ※ 획득 빈자리 표시는 §2 commit된 세션 상태로 결정되어 오리파 복귀 시 반영(**자동스크롤 없음** — STEP1 기능 제거). 리빌의 중심은 §B 히어로 연출.

### B-2. RevealProfile (연출 의미·단서 순서 분리) — 비트 배열 고정 (BLOCKER4)
| profile | 대상 | 성격 | **리빌 비트 (자동 진행, 비트당 ≤1 가속 탭 · 탭 필수 아님)** |
|---|---|---|---|
| `NUMBERED_CONFIRM_RAW` | 번호 RAW 카드 | 확정형 | *(헤더 `N번 당첨`)* → **clue: CONDITION→RARITY→SET→NAME (4)** → HERO stage |
| `NUMBERED_CONFIRM_GRADED` | 번호 그레이딩 | 확정형 | *(헤더 `N번 당첨`)* → **clue: GRADING_COMPANY→GRADE_VALUE→RARITY→SET→NAME (5)** → HERO stage |
| `SEALED_MYSTERY_RAW` | 봉인형 RAW (향후) | 추측형 | **clue: CONDITION→RARITY→SET→NAME (4)** → HERO stage |
| `SEALED_MYSTERY_GRADED` | 봉인형 그레이딩 (향후) | 추측형 | **clue: GRADING_COMPANY→GRADE_VALUE→RARITY→SET→NAME (5)** → HERO stage |
| `PACK_CONFIRM` / `GOODS_CONFIRM` | 미개봉팩/굿즈 (향후) | 확정형 | **clue: CATEGORY→NAME (2)** → HERO stage (카드 단서 필드 없음) |
- **`N번 당첨` = 오프닝 전환 헤더**(`openingLock` 중 표시, **탭 불필요**). 번호는 peel(§8)에서 이미 확정·확인 → 리빌의 탭 단서 아님. 봉인형엔 번호 없음.
- **가속 대상 = clue 비트만.** 각 clue = 1비트, 자동 진행 + 최대 1회 가속 탭(탭 필수 아님). 비트 묶기 금지(`CONDITION+RARITY`, `COMPANY+GRADE` 등 결합 금지). 프로파일 내 **clue 비트 수(=가속 가능 횟수)** 고정(불변식 §B-6.5).
- **`HERO`는 clue 비트가 아니라 최종 stage** — §B-5 규칙(탭은 등장 애니만 완료, `heroHoldMinMs` 단축 불가, 이후 `resultActions` 자동).
- `GRADE_VALUE` 비트 = 숫자 빠르게 오르다 **강하게 멈춤**.
- **번호 오리파(확정형)**: 가짜 추측 금지, 정보를 **훈장처럼 누적**해 "내 것이 되는" 카타르시스. **봉인형(추측형)**: 상품 미지 → 단서로 실제 추측.
- profile을 바꾸려면(비트 결합/분리) **오너 결정으로 재고정 후 B-2·B-7·불변식 전체 동시 수정**. "예시"로 두지 않는다.

### B-3. `RevealDescriptor` — draw와 원자 발급 + `RevealPolicy`
```
RevealDescriptor {
  profile: RevealProfile
  clues: [ { kind, displayText, emphasisTier }, ... ]   // 순서 = 공개 순서(비트), profile 표대로 고정
  heroImageRef                                           // 최종 카드/슬랩 (= prize.imageRef)
  intensity: NORMAL | RARE | HIT | JACKPOT               // 효과 강도만 (비트 수·탭 수엔 영향 X)
}
```
- **원자 발급**: `draw 실행 → 결과 확정·기록 → { prize, revealDescriptor } 함께 반환 → 클라는 반환된 것만 연출.` 뽑기 **전에 클라로 사전 다운로드/카탈로그 포함 금지**(연출 정보로 결과 유출 방지).
- **API 계약은 번호형/봉인형 동일**(백엔드 두 벌 방지).
- **mock**: 클라가 상품 **서브타입 패턴 매칭**(`RawCardPrize`/`GradedCardPrize`/`SealedPackPrize`/`GoodsPrize`)으로 `clues`를, `RevealPolicy`로 `intensity`를 파생하되, **구조는 미래 서버 발급형과 동일**.
- **`intensity`는 별도 `RevealPolicy`가 발급** (RevealConfig=모션 표현값 / RevealPolicy=정책, 분리):
  ```
  RevealPolicy { effectsEnabled; maxIntensity; intensityThresholds }
  ```
  - mock: 중앙 `MockRevealPolicy`가 `exchangePoints` 임계로 파생.
  - 미래: **서버 운영정책이 최종 intensity 발급.** 교환가는 사장님이 정하므로 **클라가 교환가만 보고 JACKPOT 자동 결정 금지**(서버 권위). `RevealDescriptor`는 이 정책의 결과물.

### B-4. `RevealConfig` — 튜닝 (하드코딩 금지)
```
RevealConfig {
  openingLockMs           // 첫 공통 오프닝 비트 입력잠금 (기본 800~1000)
  beatDwellMs             // 비트 표시 유지
  pauseBetweenBeatsMs     // ★정적 구간 = 긴장의 핵심. 튜닝값
  heroHoldMinMs           // 최종 카드 최소 유지 (기본 500~800)
  tapAdvance: true        // 탭 가속 허용
  perIntensity {          // NORMAL/RARE/HIT/JACKPOT 별
    hapticPattern, glow, particleDensity, bgScrim, sfx
  }
  reduceMotion            // OS 접근성 설정: 애니 이동·회전 축소 (사용자 설정)
  effectsQuality: LOW | STANDARD   // 기기 성능: 파티클·블러·광원 축소 (접근성과 별개 — 저사양이라고 모션 접근성을 임의로 켠 것처럼 취급 금지)
}
```
- **레퍼런스 영상 2·4 문법을 `RevealConfig` 기본값으로 작성**(영구 하드코딩 금지, 실기기 조정):
  - 영상 2: 선택 봉인물 **중앙 집중 · 주변 암전 · 개봉 직전 정적**.
  - 영상 4: **빛 축적 · 카드 옆면 회전 · 마지막 등장**.

### B-5. 탭 가속 정책 (완전 스킵 제외)
- **첫 공통 오프닝 비트 `openingLockMs`(0.8~1.0s)는 입력 잠금.**
- **각 비트는 자동 진행**한다. **탭은 선택적 가속**(비트당 최대 1회): 현재 비트 애니 즉시 완료 → 다음 비트로. **탭 필수 아님.** "건너뛰기" 텍스트 버튼 없음.
- **HERO stage 규칙**: `HERO`는 clue 비트가 **아님**. HERO에서 탭하면 **등장 애니메이션만 즉시 완료**한다. **`heroHoldMinMs`(0.5~0.8s)는 HERO가 완전히 표시된 시점부터 새로 계산**하며 **절대 단축하지 않는다**(빠른 탭에도 감상 시간 안 줄어듦). hold 종료 후 **`resultActions` 자동 노출**(탭으로 결과창 직행 불가).
- **완전 스킵(결과창 직행) 없음** — 리빌 기능 무력화 방지.
- 반복 뽑기는 탭 연타로 빠르게(비트/탭 수는 프로파일 고정이라 반복해도 구조 동일 → 학습·조작감 없음).

### B-6. 불변식 (반드시 유지)
1. 결과(prize)는 **§2 `[1구 뽑기]` 확정(commit) 시점에 확정·기록**한다. ⚠️ **용어**: "확정 시점"은 §2의 결제·commit 순간이며, §7 "봉인물 자동 추출" **애니메이션과 무관**하다(추출·peel은 이미 정해진 결과의 *표현*일 뿐, 결정 지점 아님). `revealing` 중 **RNG·결과 변경 절대 없음**(감사 근거 + 상태꼬임 방지).
2. draw 결과와 `RevealDescriptor`를 **원자적으로 함께 발급**. 사전 다운로드 금지.
3. **재진입/이탈 복구 — 범위 구분(프로세스 종료 ≠ 화면 재진입):**
   - **현재 mock**: `revealing` 중 route pop · 화면 재생성(dispose→rebuild) · 일시 백그라운드 복귀 → **세션 `activeDraw`가 살아있으면 애니 리플레이 없이 확정된 최종 상태로 복구**(컨트롤러 정리 + `mounted` 가드, 진행 중 route pop 차단은 §13). ⚠️ **프로세스 종료·앱 강제 종료는 복구 보장 안 함** — in-memory라 §11 "앱 재시작 = 초기값 리셋(영속 0)"과 일치. (`dispose`/`mounted`는 실행 중 콜백 안전성만 해결, 프로세스 회수까지는 아님.)
   - **백엔드 연동 후**: commit 결과를 서버에 기록 → 재진입 시 draw 상태 조회 → `activeDraw.status(COMMITTED / REVEALED / RESOLVED)`에 따라 최종 상품 복구.
4. `revealing` 중 **탭 가속 외 입력·중복 액션 잠금.** 탭은 **현재 비트 완료를 1회만 트리거(래치/디바운스)** — 애니 콜백 중복 실행·비트 스킵 금지.
5. **같은 profile 내에서 NORMAL/HIT는 clue 비트 수·구조·가속 가능 횟수 동일.** (탭 필수 아님 — clue당 ≤1 가속. `HERO` stage는 가속 대상 아님, §B-5.) 차이는 배경·사운드·햅틱·빛의 **강도만**. ※ 프로파일별 clue 비트 수는 **고유**(§B-2 표) — `PACK/GOODS`를 카드 프로파일 길이에 맞추려 **빈 비트/억지 정보 패딩 금지**(자기 프로파일 자연 길이).
6. **공통 오프닝 비트에서는 RAW/슬랩 여부를 노출하지 않는다**(GRADED≠고가라 tell 아님) → **첫 단서(`CONDITION`/`GRADING_COMPANY`)에서 공개.** RAW/GRADED 프로파일은 구조가 달라도 됨(상품형태 고유).
7. 연출 강도는 **법률·운영정책에 따라 서버(`RevealPolicy`)에서 낮추거나 끌 수 있어야 한다**(데이터 주도). ※개봉 전후 분리는 공정성/UX 설계이지 사행성 "해결"이 아님 — 출시 전 법률 검토 별도 필요.

### B-7. 프로토타입 3종 (순수 Flutter, 번호 오리파=`NUMBERED_CONFIRM`) — 비트 배열 §B-2와 동일
> 파티클/글로우 에셋(Rive/Lottie)은 **아직 결정하지 않음.** 순수 Flutter(스케일·회전·블러·스크림·텍스트전환·방사광·소량 파티클·햅틱·탭가속·**정적**)로 손맛 구조 먼저 검증 → 실기기 판정 후 정말 필요한 효과만 에셋 교체. 연출 핵심 5개 = **타이밍·정적·사운드·정보 순서·최종 등장 속도.**

1. **RAW_NORMAL** (`NUMBERED_CONFIRM_RAW`, `NORMAL`) — 헤더 + **4 clue** + HERO stage
   `[47번 당첨]` → RAW → RR → 스칼렛 ex → 가디안 ex → **HERO stage**
2. **RAW_HIT** (`NUMBERED_CONFIRM_RAW`, `HIT`) — 헤더 + **4 clue** + HERO stage
   `[47번 당첨]` → RAW → SAR → 테라스탈 페스타 ex → 블래키 ex → **HERO stage**
   → **RAW_NORMAL과 clue 비트 수·가속 가능 횟수·타이밍 동일, 강도(빛·사운드·햅틱)만 상승** (불변식 5).
3. **GRADED_HIT** (`NUMBERED_CONFIRM_GRADED`, `HIT`) — 헤더 + **5 clue** + HERO stage
   `[18번 당첨]` → BRG → 10 → AR → 인페르노 → 팽도리 → **HERO stage** (`10` = 숫자 카운트업→강하게 멈춤)
> `[N번 당첨]` = 오프닝 헤더(탭 불필요). **clue 비트만** 자동 진행 + 선택적 가속. `HERO`는 등장 애니만 가속 · `heroHoldMinMs` 보존 후 `resultActions` 자동(§B-5).

---

## 9. 번호 확인 → (리빌) → 상품판 반영 (BLOCKER1 수정)
- 번호 전체 공개 후 **자동 전환 금지.** 약 0.8s 유지 후 `[N번 상품 확인하기]` CTA → 유저 탭 → **§B `revealing`.**
- ★**`taken` 처리는 §2 commit에서 이미 완료됨** — 리빌 완료(`revealed`) 후 **새로 갱신하지 않는다**(중복 갱신·화면별 남은구수 불일치 방지). 오리파 상세로 복귀하면 **commit된 세션 상태를 읽어** 해당 번호를 "획득됨" 빈자리로 표시. **flip 금지**(상품은 뽑기 전부터 앞면). **자동스크롤 없음** — 복귀 시 상품판이 갱신된 상태로 보이면 됨.

## 10. 결과 & 후속 액션 (`resultActions`)
```
[상품 히어로 이미지]
{번호}번 상품 · {상품명} · 교환 {P}
[보관하기]   [{P}로 교환]
```
- 리빌 `revealed` 히어로 감상(≥`heroHoldMinMs`) **이후에만** 결과 액션 노출(감동을 UI가 덮지 않게).
- **보관하기**: 매장별 mock 보관함 세션 내 `+1` → `[다시 뽑기 · 50,000 P]` / `[오리파로 돌아가기]`.
- **포인트 교환**: 세션 mock 포인트 `+exchangePoints` → 갱신 표시 → 동일 액션.
- ★**보관·교환은 한 번만 처리되는 래치**(연타로 `held +2` / 포인트 2회 추가 금지). 실행 시 `activeDraw.status=RESOLVED` + `resolution(KEEP/EXCHANGE)` 기록, **RESOLVED 후 재실행 무시**.
- **다시 뽑기**: 누를 때마다 **확인 바텀시트 재표시**. 잔액 부족 시 disabled + "포인트가 부족합니다".

## 11. 세션 mock 상태 (BLOCKER2: activeDraw 추가)
- `OripaSession extends ChangeNotifier` **싱글톤**. 화면은 `ListenableBuilder` 구독.
- 보유: `points`(시드 125,000) · `held` · `Map<oripaId,Set<int>> taken` · `Map<oripaId,int> drawCursor` · **`activeDraw`**(진행 중 뽑기, §B-6.3 복구 대상).
```
ActiveDraw {
  drawId
  oripaId
  number
  prize
  revealDescriptor
  status: COMMITTED | REVEALED | RESOLVED
  resolution: KEEP | EXCHANGE | null
}
```
- **상태 전이(고정)**: `confirmDraw()` → `COMMITTED` / hero 공개 완료 → `REVEALED` / 보관·교환 1회 실행 → `RESOLVED`.
- **수명주기(고정)**: `COMMITTED`/`REVEALED` 중 **새 draw 시작 금지**(한 번에 하나). `RESOLVED` 후 → 보관/교환 재실행 무시 · **`[오리파로 돌아가기]` 완료 시 `activeDraw` clear** · **`[다시 뽑기]` 확인 후 새 draw로 원자 교체**. (옛 `RESOLVED` draw가 남아 재진입 시 옛 결과를 재노출할지 여부의 모호함 제거.)
- **뽑기 확정(§2 commit)**: `pricePerDraw` 차감 + 번호 taken 추가 + drawCursor 이동 + prize·RevealDescriptor 확정(mock 파생) + `activeDraw` 생성(COMMITTED). `[1구 뽑기]` 첫 탭 후 즉시 비활성화.
- 보관 시 held +1 / 교환 시 points += exchangeP → `RESOLVED` + `resolution` 기록(래치, §10).
- 미래 백엔드: `drawId`(idempotency key)로 동일 계약 유지.
- **앱 재시작 = 초기값 리셋(`activeDraw` 포함). 영속/API/DB/원장 0.**

## 12. 남은 구수 반영 범위
- **동적**: `oripa_detail_screen` + `shop_detail_screen` 둘 다 세션 기반 `남은 N구` 실시간 반영.
- **정적(이번 범위 밖)**: `shop_list_screen` "진행 중 N개", 매진 active count.

## 13. 뒤로가기 정리
- 확인 시트 전: 일반 뒤로가기 가능.
- `[1구 뽑기]` 확정 후 ~ 결과(보관/교환) 전: **뒤로가기 차단**(§6 안내). `revealing` 중 재진입은 `activeDraw` 최종 상태 복구(불변식 §B-6.3).

## 14. 디자인 원칙 — "가챠 금지 ≠ 디테일 금지"
- **개봉 전(추출·peel)**: 게임 이펙트 대신 **실제 카드를 손으로 다루는 물리감**(카드 두께·접촉 그림자·마찰·미세 회전·덮개 후행·햅틱). 티어/JACKPOT/사전 전조/파티클 **금지**.
- **개봉 후(`revealing`)**: 프로파일·강도에 따라 빛·정적·사운드·정보 순서로 카타르시스 연출 **허용**. 단 §B 불변식 준수(같은 profile 내 구조 동일, 강도만 차등, 서버 조절 가능).
- 신규 UI는 기존 토스 디자인 문법(`AppText`/`AppRadius`/`Pressable`/`EmptyState` 등), 하드코딩 색상·불필요한 외곽선·글로우 금지(리빌 연출 글로우는 `RevealConfig` 경유).

## 15. 후속 부채 (이번 범위 제외, TODO)
- 접근성: 드래그 까기가 유일 오픈 수단 → VoiceOver/스위치 대체 개봉 경로 없음. (리빌 `reduceMotion`은 포함.)
- 봉인형 오리파(sealed) 추측형 리빌 = 다음 기능(엔진 재사용).
- 상품 이미지: 렌더 타일 mock → 파트너센터(사장님 업로드) 교체. 카드 CDN 재사용 금지.
- shop_list "진행 중 N개" / 매진 active count 동적화.

## 16. 상태 & 이어가기 (2026-07-10 재개정)
- **STEP 1+2(개봉까지) 구현완료** (feat/oripa-1.2.0). TestFlight 1.2.0 build `202607082352`.
- **개정 확정(2026-07-10)**: 개봉 후 결과 리빌 도입(§B). A안=(번호=확정형/봉인형=추측형), B안=(사장님 입력 판매속성). **GPT 리뷰 BLOCKER 4건 반영**: ①taken=commit 단일화(§2·§9·§11) ②`activeDraw` + 단일 resolution 래치(§10·§11·§B-6.3) ③상품 모델 종류별 필수 필드·`condition`/`characterDisplayName` 제거·`OTHER` 제거(§5) ④리빌 비트 배열 고정 B-2↔B-7 통일. 수정권장: `RevealPolicy` 분리(§B-3)·`reduceMotion`/`effectsQuality` 분리(§B-4)·`imageRef`(§5).
- **조건부 승인 패치(2026-07-10)**: ①`cardPresentation` **타입 계약** ②**탭=선택적 가속**(강제 아님)·`N번 당첨`=오프닝 헤더 ③`activeDraw` **수명주기**(RESOLVED clear/원자 교체 §11).
- **최종 승인 패치(2026-07-10)**: ④`OripaPrize` **`sealed` 타입 확정**(`RawCardPrize`/`GradedCardPrize`/`SealedPackPrize`/`GoodsPrize` — nullable/`null 고정` 모순 제거, 리빌 프로파일=타입 패턴 매칭, §5) ⑤`HERO`를 **clue 비트와 분리한 최종 stage**(탭=등장 애니만, `heroHoldMinMs` 단축 불가, 이후 `resultActions` 자동 §B-2·B-5·B-7).
- **구현 실행 순서(스펙 승인·커밋 후)**:
  1. ✅ 스펙 개정(이 문서)
  2. `OripaPrize` **sealed 모델** (`RawCardPrize`/`GradedCardPrize`/`SealedPackPrize`/`GoodsPrize`)
  3. `RevealDescriptor` / `RevealPolicy` / `RevealConfig` / `RevealProfile` (§B-2·B-3·B-4)
  4. 상태머신 `extracting→peeling→revealing→revealed→resultActions` + `activeDraw` 복구·입력락 (§B-1·B-6·§11)
  5. 순수 Flutter 프로토 3종 (§B-7)
  6. 실기기 손맛 판정 → Rive/Lottie 여부 결정
- **그 후**: 봉인형 오리파(추측형 리빌) → 파트너센터(사장님 등록 UI) → 내부 Admin 승인 → 백엔드(SHOP/ORIPA/SLOT/DRAW/WALLET/LEDGER/HOLDING/SHIPMENT/SETTLEMENT).
