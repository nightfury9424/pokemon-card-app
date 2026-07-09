# KO 시세 동기화 파이프라인 — 정상 플로우 vs 2026-06-18 실제 사고

> 작성: 2026-06-19 새벽 (사고 직후). 이번 세션에서 prod 데이터/로그/코드로 검증한 내용 기준.
> 결론 먼저: **데이터 수집층(scrydex)은 정상. 문제는 교정층(base 소스선택 + v6 오버레이)이고, 재설계 대상은 거기다.**

---

## 0. TL;DR

- **설계 의도**: 매일 밤 `해외 raw(JP/EN) × 레어도계수`로 KO 예상가 생성 → v6가 하향교정 → chart_price로 표시 생동감.
- **실제**: base가 **EN을 과선택(KO엔 틀림)**해서 ~1,750장이 인플레된 값으로 나오고, **v6 down-only가 매일 그걸 깎아 가리는** 2단 구조. 이 구조가 깨지기 쉬움.
- **2026-06-18 사고**: ① v6가 23:52에 **실행 자체가 안 됨** — 낮 수동 v6(root)가 그날 로그파일을 `root:root`로 만들어 ubuntu cron이 append 실패→래퍼 즉사(**운영/권한 사고, 모델 버그 아님**) → base 인플레 대량 노출(꼬부기 60k, 글레이시아 67k 등) ② v6가 (수동으로) 돌아도 **사각지대 ~24장**은 못 깎음(모델 사각지대) ③ chart_price wiggle이 **프로모에도 적용**돼 가짜 전일대비(카나자와 +2.4%).
- **핵심 메타**: ①은 운영 풋건(한 줄 권한), ②③은 모델/스크립트 결함. **mass 폭등의 방아쇠는 운영사고지 모델 재설계 부재가 아님.** 게다가 **매일 낮 응급 수동수정이 그날 밤 자동화를 부순다**(스톱갭→다음 사고 루프).
- **판단**: 교정층(base+v6) **재설계 권장**(JP-first로 base를 애초에 맞춰 v6 마스크 제거). 데이터 수집은 유지.

---

## 1. 예상했던 정상 플로우 (설계 의도)

### 1-1. 파이프라인 단계 (KST, 매일 밤)

| 시각 | 단계 | 실행 | 역할 |
|---|---|---|---|
| ~21:00–23:30 | scrydex 수집 + 계수 | Spring @Scheduled | JP/EN raw 갱신, 계수 산출 |
| **23:45** | **base 생성** | Spring @Scheduled `refreshKoEstimatesFromSnapshots` | 오늘자 KO_ESTIMATED 삭제 후 재생성. `JP/EN raw × 레어도계수` + 소스선택(JP/EN 히스테리시스). audit 기록 |
| 23:50 | hold_outliers | host cron | 일일 급변동 hold |
| **23:52** | **v6_apply** | host cron `v6_apply_daily.sh` | **down-only 교정** (NORMAL 하향, DAANGN/HIT/MANUAL_FLOOR 등). 인플레 base를 KO현실로 끌어내림 |
| 23:55 | sanity_cap | host cron | 극단값 cap |
| **23:57** | **chart_price** | host cron `ko_chart_price_daily.sh` | 표시 생동감: `chart_price = price × (1 ± 1.5% 난수)`. **KO 비프로모만** (프로모 제외해야 함) |

### 1-2. 계수
- **rarity 계수** (`ko_coef_jp_AR`, `ko_coef_en_SR` …): **주간(월요일)** 재계산, NAVER_CAFE 60일 윈도우. price_snapshots SYSTEM 행.
- **global 계수**: 매일 갱신이나 **`FROZEN_GLOBAL_COEFFICIENT=0.478`로 동결**.
- (주의) live 계수는 `ko_price_coefficients` 테이블 아님 — 그건 5/15·5/26 BOOTSTRAP 잔재. 진짜는 `price_snapshots`의 `ko_coef_*` SYSTEM 행.

### 1-3. 표시 규칙
- **대표가/차트/셀/자산/전일대비/급변동보드** = `getDisplayPrice()` = `COALESCE(chart_price, price)`.
- `price` = 내부 anchor(시세로직 전용), `chart_price` = 표시용 ±1.5% wiggle.
- **프로모(`is_promo_exclusive=true`)**: chart_price 적용 **금지**. 해외참고가(JP) 그대로 flat 표시.
- JP/EN 차트는 실제 시장값(안 건드림).

### 1-4. 대표 카드 — "정상가" (= 6/17 검증값, frozen 기준)

| 카드 | 레어도 | **정상가(원)** | 소스 |
|---|---|---|---|
| 꼬부기 (8B51) | AR | **16,281** | JP-path |
| 꼬부기 (A90A) | AR | **21,700** | |
| 이브이 (A5B0) | AR | **15,598** | JP-path |
| 이브이 (F285FE) | AR | **2,580** | |
| 글레이시아 | HR | **10,303** | |
| 파이리 | AR | **13,046** | |
| 이상해씨 | AR | **13,051** | |
| 볼트로스 EX플라스마단 | SR | **14,319** | |
| 카나자와 피카츄 | PR(프로모) | **202,640** (해외참고가 JP, flat) | PROMO/JP |

> 불변식(설계): **KO < JP raw, KO < EN raw** (한국가는 해외 raw보다 쌈). 전 카탈로그 99.9%가 이 불변식 충족이 정상.

---

## 2. 실제 동기화 사고 (2026-06-18 밤)

### 2-1. 타임라인 (실측)

| 시각 | 사건 |
|---|---|
| 23:38 | (사전 dry-run) base 미리보기 = 3,748/3,748 정상, partialFailure=false ✅ |
| 23:45 | **base 정상 완료** — 3,749장 저장 (refresh 완료). 6/15식 prevSource 붕괴 **안 일어남**(가드 작동) |
| 23:52 | **v6 cron 발동(syslog 확인) — 그러나 commit/log 없음. 적용 실패** ← 핵심 사고 |
| 23:57 | chart_price cron 실행 — **인플레된 base값에 wiggle** 입힘(스파이크 + 가짜 생동감) |
| 00:06~ | (수동) v6 재실행 1,738장 교정 + 사각지대 복구 + 전체 6/17 덮어쓰기 → 클린 |

### 2-2. 무엇이 터졌나 — 3개 (전부 교정층 = 동기화 하류)

#### ❌ 문제 A — v6가 23:52에 **실행 자체가 안 됨** (mass 스파이크) — 원인 확정
- **확정 원인 = 로그 파일 권한 풋건 (운영 사고, 모델 무관).**
- 증거 체인:
  1. syslog: `2026-06-18T23:52:01 CRON (ubuntu) CMD (v6_apply_daily.sh)` = cron은 떴음. **바로 다음 줄 `CRON info (No MTA installed, discarding output)`** = 작업이 stdout/stderr로 출력을 냈고 cron이 그걸 버림.
  2. 래퍼 `v6_apply_daily.sh`: `set -e` 후 `exec >>"$LOG" 2>&1` → `echo "=== start ==="` → `docker exec ... v6_apply.py`. 즉 로그 redirect가 **echo·docker exec보다 먼저**.
  3. `v6_apply_20260618.log`에 **23:52 "start" 줄조차 없음**(04:09·13:55만). echo 전에 죽었다는 뜻 = `exec >>"$LOG"`에서 실패.
  4. `ls -l`: 6/18 로그 = **`root:root -rw-r--r--`, 13:55 작성**. 반면 6/13~6/17 로그는 전부 `ubuntu:ubuntu -rw-rw-r--`.
- **메커니즘**: 낮 13:55(또는 04:09) 수동 v6를 **root(sudo)로** 실행 → 그날치 로그파일이 root 644로 생성 → 23:52 ubuntu cron이 같은 파일 append 시도 → **권한 거부** → `set -e`로 래퍼 즉사 → v6 본체(`docker exec`) 도달 못 함 → base EN-인플레 안 깎이고 노출.
  - 6/17 대비 점프: **>4x 1장, 2~4x 44장, 1~2x 315장** (총 ~360장).
- (정정) 내 초기 진단 "백업테이블 존재→abort(sys.exit 6)"는 **틀림** — abort였다면 로그에 "start"+"ABORT" 줄이 남았어야 함. 실제는 로그 진입 전 사망. v6_apply.py·v6 모델 자체는 멀쩡(직후 수동 DRY_RUN would change 1779).
- **재발조건**: "그날 낮에 v6를 root로 수동실행" → 그날 밤 cron 사망. 즉 **우리 응급수정 습관이 방아쇠.** (백업테이블 abort 가드 sys.exit 6 도 별개 함정 — 같은 날짜 수동 commit 후엔 그 가드로도 막힘.)
- **예방**: ①수동 v6는 ubuntu로 실행(sudo 금지) ②래퍼에 로그 chown/`chmod 666` 또는 사용자별 로그 분리 ③근본은 base 동결로 v6 의존 자체 제거.

#### ❌ 문제 B — v6 사각지대: 돌아도 안 깎이는 카드 ~24장
- v6를 수동으로 정상 실행했는데도 **24장이 6/17 대비 >1.5x로 남음**:
  - 글레이시아 HR 10,303→67,596 (**6.56x**), 파이리 AR 13,046→63,392 (4.86x), 꼬부기8B51 16,281→59,994 (3.68x), 이상해씨 AR (3.68x), N의각오 SR (4.73x) …
- 이 카드군은 로컬 테스트 때도 동일하게 안 깎였음 = **v6 로직의 구조적 사각지대**(KEEP_NODATA / NORMAL_HELD 등으로 빠져 down-교정 대상에서 누락 추정).
- 추가로 1.1~1.5x 점프 68장(볼트로스 EX플라스마단 +33% 포함) — 차트에 절벽으로 보임.

#### ❌ 문제 C — chart_price wiggle이 프로모에도 적용 (가짜 전일대비)
- `ko_chart_price_daily.sh`와 freeze UPDATE 둘 다 `WHERE source='KO_ESTIMATED'`만 걸고 **프로모 제외 없음**.
- 프로모 KO_ESTIMATED **1,458행**이 wiggle 먹음 → 표시는 JP 해외참고가인데 전일대비만 wiggle로 계산돼 **카나자와 피카츄 +2.4%** 같은 가짜 변동(차트는 수평인데 % 뜨는 불일치).

### 2-3. "정상가 vs 사고시 값" 대표 비교

| 카드 | 정상가 | 사고시(6/18) | 배율 | 원인 |
|---|---|---|---|---|
| 글레이시아 HR | 10,303 | 67,596 | 6.6x | v6 사각지대(B) |
| 파이리 AR | 13,046 | 63,392 | 4.9x | v6 사각지대(B) |
| 꼬부기 8B51 AR | 16,281 | 59,994 | 3.7x | EN과선택+v6 미적용(A) |
| 이상해씨 AR | 13,051 | 47,978 | 3.7x | (B) |
| 이브이 A5B0 AR | 15,598 | 46,454 | 3.0x | EN과선택+(A) |
| 볼트로스EX플라스마단 SR | 14,319 | 18,949 | 1.33x | v6 사각지대(B) |
| 카나자와 피카츄 PR | 202,640(flat) | +2.4% 가짜변동 | — | 프로모 wiggle(C) |

---

## 3. 배경: 만성 구조 문제 (이번 사고의 토양)

1. **EN 과선택** — base는 JP/EN 발산>임계면 EN 채택. 근데 **KO=일본시장**이라 JP 타야 맞음. ~1,750장이 EN 기준 과대.
2. **계수 인플레** — `en_AR` active ~0.34 vs 실거래 median ~0.075. NAVER_CAFE obs 오염(해외 시세 인용)이 계수에 섞임.
3. **ground-truth 부재** — 진짜 KO 실거래(DAANGN)는 **5/19에 수집 죽음**. 살아있는 NAVER는 오염. 계수를 믿을 근거가 없음.
4. **2단 모델 의존성** — base(틀림) + v6(가림). **표시 정확성이 둘 다 매일 완벽 실행에 의존.** v6가 한 번 안 돌면(=오늘) 전부 노출.
5. **frozen** — v6 6/14 상수 + global 0.478 동결. 시세가 시장을 안 따라감(정적). chart_price가 그걸 살아보이게 위장.
6. **6/15 사고 메커니즘(이미 가드로 차단됨)** — base 부분실패→prevSource 기아→히스테리시스 붕괴→대량 flip→v6 gate abort. → `refreshKoEstimatesFromSnapshots`에 부분실패/입력 ABORT 가드 추가(커밋 b1fa9694, 배포됨). **오늘은 이 경로로 안 터짐(가드 작동). 다른 경로(A/B/C)로 터진 것.**

---

## 4. 오늘 적용한 응급 복구 (스톱갭)

1. v6 수동 실행 → 1,738장 down-교정.
2. 사각지대 24장 + 점프 68장 → 6/17값 복구.
3. **6/18 KO 전체(3,749장)를 6/17 클린값으로 덮어쓰기** = 완전 frozen 일치(편차 0).
4. 프로모 chart_price 1,458행 NULL + cron에 프로모 제외 추가.
5. back 재시작(캐시 클리어).

**백업(롤백 가능)**: `ko_v6enbr_rollback_20260618`, `ko_spike_fix_backup_20260619`(24), `ko_spike_fix_backup2_20260619`(68), `ko_6_18_prefreeze_backup_20260619`(3749), `ko_chart_price_daily.sh.bak_promo_20260619`.

> ⚠️ **이건 오늘밤 한정.** 내일 23:45 nightly가 또 돌면 같은 A/B(/C) 재발 가능. 내일 23:45 전에 근본 처리 필요.

---

## 5. 재설계 판단 — "구조 다시 짤지"

### 유지할 것
- **scrydex 수집(JP/EN raw)** — 정상. 그대로.

### 갈아엎을 것 (교정층)
현재 `base(EN과선택, 틀림) + v6(down-only 마스크, 깨지기 쉬움)` 2단 구조가 사고의 근원.

**제안 = JP-first 단일모델**:
1. **base 소스선택을 JP-first로** — KO=JP시장이므로 발산해도 JP 우선(EN-only/검증된 chase만 EN 앵커). → base가 **애초에 맞는 값**을 냄.
2. **v6 down-only 오버레이 제거/축소** — base가 맞으면 마스킹 불필요. (현 v6의 실행 신뢰성·사각지대 문제 자체가 사라짐.)
3. **계수 디인플레** — NAVER 오염 배제, DAANGN 실거래 수집 복구해서 ground-truth 위에 재캘리.
4. (그때까지 임시) **nightly를 "어제 클린값 copy-forward + wiggle"로** = 스파이크 원천 차단하며 frozen 유지.

> 6/18에 로컬에서 JP-first 재동기화 검증해둔 결과 있음(이브이 46,873→16,247, 꼬부기 64,698→13,563 등 2,987장). 이게 1·2·3의 프로토타입. 단계검증 후 배포.

### 내일(6/19) 23:45 전 — 현실 점검
- 내 6/18 전체 덮어쓰기는 **내일 base가 6/19를 재생성하며 지워짐**(영속 아님). 즉 내일 밤 파이프라인이 또 돈다.
- 6/19 로그파일은 아직 없음 → 내일 cron은 새 파일을 ubuntu로 생성 → **문제 A는 (낮에 root 수동실행만 안 하면) 재발 안 함.** 단 v6가 돌면 **문제 B 24장은 또 스파이크**(글레이시아 67k 등), base EN-인플레 잔여도 v6 down-only가 못 잡는 부분 노출 가능.
- 결론: 내일 밤 = mass(A)는 아니어도 **B+드리프트로 또 더러워짐.** 가만 두면 또 새벽에 수동복구 = 루프 5일째.

### 우선순위 (택1 결정 필요)
1. **(긴급/안전 최우선) nightly mutation 동결** — base 재생성·v6·chart cron을 멈춰 현재 클린값을 고정. 23:45 시한폭탄 제거 후 차분히 재설계. (대가: 시세 정적, 근데 어차피 frozen이라 손해 없음.)
2. **(대안) 하드닝 후 계속 가동** — 로그 권한 fix + 문제 B 24장 v6 커버 + 프로모 제외(완료). 단 base EN-인플레 의존은 그대로라 깨지기 쉬움.
3. **(근본) JP-first 재설계** — base를 애초에 맞춰 v6 마스크 제거. dry-run 검증분 있음. 1·2 위에서 차분히.

> ★권장: **1번(동결)**. 4일 연속 새벽 수동복구의 진짜 해법은 "더 잘 고치기"가 아니라 "터질 자동화를 잠시 끄기". 동결은 prod cron 주석처리(롤백=주석 해제)라 가역적·저위험. base @Scheduled 중단법(env 플래그 유무)만 확인 필요.

---

## 부록: 핵심 파일/위치
- base: `back/.../price/GlobalPriceService.java` (`refreshKoEstimatesFromSnapshots`=1497, `inferPrevKoSources`=2689, 히스테리시스 SPREAD 34-40, `FROZEN_GLOBAL_COEFFICIENT`=0.478)
- v6: prod `/opt/pokefolio/scripts/v6_apply.py` (33KB), 실행 `/opt/pokefolio/cron/v6_apply_daily.sh` (host cron 23:52)
- chart_price: `/opt/pokefolio/cron/ko_chart_price_daily.sh` (23:57)
- 계수: `price_snapshots` SYSTEM 행 `ko_coef_*`
- 관련 메모리: project_price_root_coef_20260618, project_chart_price_liveliness, project_price_corruption_20260615, project_chase_pricing_model_status

---

## 부록 B — 2026-06-19 새벽 심층진단 (재설계 근거, prod/코드/CSV 검증)

### B-1. "테스트는 맞는데 동기화는 틀린" 이유 = 테스트가 모델이 아니라 freeze였음
- `python/price_0615_backfill/recompute.py` = 운영 base **충실 재현**(suspect→spread 2.0/2.2/1.8 prevSource→raw×coef). 실행: 6/14 source일치 98.8%, ko일치 86.6%(=13%는 앵커/플로어/당근/flip 등 override 필요분).
- 단 "교정값"=재계산값이 **아니라** `k14`(6/14 last-good JP값) carry-forward. recomp값은 코드가 "참고용(±노이즈)"라 명시.
- 결론: 테스트=오염감지+freeze 검증. base는 모델출력 그대로 write, v6는 freeze(FROZEN_KOVALS=6/14값) override. divergence는 v6 override 실패시(오늘=로그권한 / B=freeze셋 누락)에만. **→ 검증된 동작 모델이 어디에도 없음.**

### B-2. ★진짜 모델병 = flip 아니라 LEAVE_EN(EN 과선택)
- 오늘 헤드라인 폭등(글레이시아·파이리·꼬부기8B51·이브이·이상해씨) = 전부 `prod_s14=EN/s16=EN/recomp=EN` = **안정적 EN 선택(flip 아님).** 실제 flip은 85장(FIX_TO_JP 78 + ANCHOR_NEEDED 7) 별도·소수.
- `select()` 규칙: JP·EN이 ~2배(2.0/2.2/1.8) 넘게 벌어지면 **EN 선택.** KO=JP시장인데 발산시 EN신뢰=거꾸로. LEAVE_EN ~1,535장.
- `suspect()` 비대칭: `jpk/enk>8 → 의심`(JP만), **EN이 높은 건 의심 안 함** → 오염/고평가 EN 무방비.

### B-3. en_coef 과대 + EN 데이터 graded 오염 (복리)
- 꼬부기8B51: JP $30(45,250원) vs EN $118(178,766원). base=EN×0.34≈61k(틀림). **JP×0.36=16,500=정답(16,518).** 파이리도 JP×0.35=14,780=정답. → **JP-first면 AR은 계수 안 건드려도 맞음(수치 증명).**
- en_coef: 실제 KO/EN≈0.09인데 시스템 0.34 = **3.7배 과대.**
- 글레이시아 HR(DP 빈티지) SCRYDEX_EN = 전부 **GRADED PSA10(16,098,628원)/PSA9** — 클린 RAW EN 없음. **graded가 RAW와 같은 source에 `card_status`로만 구분** → 필터 누락시 즉사. ratio 20x = 데이터에러 신호.

### B-4. 재설계 5기둥 (확정)
①소스선택 **JP-first**(발산시 JP) ②**en_coef 재캘리**(0.34→실측 ~0.09) ③**수동핀 영속 저장소**(price_snapshots는 base가 매일 덮음 → 별도 anchor/override 테이블) ④**v6 제거** ⑤**EN 데이터 위생**(graded 엄격제외 + graded-only/8x+divergence EN은 'EN없음'→JP fallback, suspect 비대칭 반전).

### B-5. ground-truth 시드 배치1 (사용자 수집 대기 — raw/민자·한국판·blind)
23장 = 헤드라인 AR4 + 고가chase9(메가리자몽Y·리자몽GX/V·제크로무·가디안·레쿠쟈·피카츄V·블래키GX·지우피카츄) + 빈티지/EN의심3(글레이시아·토대부기·리자몽CHR) + 레어도캘리브7. 수집 후 레어도별 KO/JP_raw 역산 → JP-first **외부 정확성** 검증(지금까진 내부 일관성만). **미수집 OK(비긴급).** ★대안: DB의 기존 실거래(DAANGN 476·APP_TRADE·번장)를 먼저 긁어 시드 자동채움 → 사용자는 갭만 확인.
- ★DAANGN 기존값 8/23 보유: 제크로무 135k(n=7,강함)·이상해씨 11k·메가팬텀 10.5k·메가망나뇽 10k·레쿠쟈VMAX 95k(모델3배낮음!)·리자몽V 50k·**꼬부기8B51 4,500(n=1,frozen 16,518의 1/3.7!)·파이리 2,000(n=1)**. → **frozen 정답값도 인플레였음 확정.** 단 n=1·2~3개월전은 참고값(앵커 금지). 진짜 jp_coef(AR)≈0.10 의심(0.35 아님). 강한 앵커는 제크로무 n=7뿐.

---

## 부록 C — 2026-06-19 02:21 FREEZE 배포 완료 (출혈 멈춤, ≠치료)

**상태**: prod nightly price 파이프라인 동결. base는 더는 매일 재생성 안 함 → 현재 clean 6/18값 정지.

**적용 내용**:
1. **base**: `PriceSyncScheduler.refreshKoEstimates()`(⑥, cron 0 45 23)에 `@Value("${price.sync.enabled:true}")` guard 추가 + `@PostConstruct` 부팅로그. `.env.prod`에 `JAVA_TOOL_OPTIONS=-Dprice.sync.enabled=false`. 부팅로그 `[PriceSync][FREEZE] price.sync.enabled=false` 확인 → 23:45 SKIP 확정.
2. **host cron 4개**(hold_outliers/sanity_cap/v6_apply/ko_chart_price) → `#FREEZE20260619` 주석.

**★작업 원칙 (dirty prod)**: prod=`integ/prod-consolidated` HEAD 060c741, **working-tree 39파일 dirty/미커밋 핫픽스**(card-add·hoga·readonly·chartfix 등). → **git checkout/pull/reset/stash 절대 금지.** working-tree 직접 surgical patch + `docker compose up -d --build --no-deps back`(빌드가 working-tree 사용 → 핫픽스 보존). git 명령 0개로 완료.

**백업**: `/opt/pokefolio/backups/price_freeze_20260619_021707/`(PriceSyncScheduler.java.bak·env.prod.bak·docker-compose.bak·back_src_snapshot·prod_worktree.diff 790줄·crontab) + DB `price_snapshots_bak_20260619_021707`(1,213,076행).

**롤백**: `.env.prod`에서 `JAVA_TOOL_OPTIONS` 줄 제거 → cron `#FREEZE20260619` 주석 해제 → `docker compose -f /opt/pokefolio/app/docker-compose.prod.yml up -d --build --no-deps back`. (code default=true라 env만 빼도 base 부활.)

**⏳ 미관측 최종확정**: 오늘 23:45~57 — 신규 `6/19 KO_ESTIMATED` row 0건 + `⑥ SKIPPED` 로그.

**다음 = 치료 단계** (freeze로 23:45 시한폭탄 제거됨 → 차분히): ①base 소스선택 JP-first 반전 ②en_coef 재캘리(외부 실거래 ground-truth 기반) ③EN graded 위생 ④수동핀 영속 저장소 ⑤v6 제거. shadow-run·단계 컷오버·빅뱅 금지.
