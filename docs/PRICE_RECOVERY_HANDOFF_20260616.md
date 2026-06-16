# 시세 재보정 핸드오프 — 2026-06-16 (v2, 진단 전면 교체)

> **다음 세션 시작점.** 이 문서의 v1(audit 복구 전제)은 **틀렸고 폐기됨.** 아래가 검증된 새 진단.
> 핵심 한 줄: **AR live 가격은 이미 대체로 맞다. 망가진 건 base 모델 계수(2~4.6배 과대)와 audit. 복구가 아니라 "모델 계수 재보정"이 답.**

---

## 🟢 적용된 prod 변경 (이력)
- **2026-06-16 P0** ✅: `/opt/pokefolio/cron/sanity_cap_extreme_daily.sh` held 리스트에 **MANUAL_ANCHOR/FLOOR 18장 추가**(14→32). 목적=23:55 sanity가 모야모(SAR 148,800) 등 수동앵커를 cap으로 깎는 사고 방지. Codex 사전검토 GO(18 id=v6_apply.py 일치). 검증: 모야모 cap 대상에서 PROTECTED 확인. **백업** `...sh.bak_20260616_preanchor`, **롤백** `sudo cp .bak_20260616_preanchor ...sh`. card-scope 보호는 보류(뮤츠/N레시라무 stale 의심).
- 그 외 prod 시세값/계수/스냅샷/holder pp 전부 **무변경**.
- **다음**: P0.5(월요일 03:00 rarity/card recalc 임시 disable) diff 검토 후 별도 적용.

## ⛔ v1에서 뒤집힌 것 (다시 읽지 말 것)

| v1 주장 (폐기) | v2 검증 결과 |
|---|---|
| audit = 진실원, 900장 복구 | **audit는 stage-2 모델값 = AR에선 인플레값.** 복구하면 파이리 AR을 69,072원에 파는 사고 |
| 내 6/16 스무딩이 깨뜨림 | **무죄.** live 8,000은 traded_at 6/14 = 스무딩보다 먼저. audit≠live는 매일 도는 overlay(v6/sanity)의 정상 동작 |
| 고라파덕 8,000이 버그 | **8,000이 현실에 가깝다.** 번장 실거래 6,300. 버그는 audit 57,490 (EN 인플레) |
| 0.263으로 재보정 | **0.263도 높음.** selection bias로 부풀려진 값. 실측 ~0.16~0.18 |

---

## ✅ v2 검증된 사실 (전부 이번 세션 데이터)

### 1. 파이프라인 = 정합성 없는 3모델 last-writer-wins
| 시각 | 단계 | 동작 | KO 영향 |
|---|---|---|---|
| 23:45 | base 모델 (Java `refreshKoEstimatesFromSnapshots`) | raw×rarity계수 + **spread가드(EN/JP 2배↑면 EN선택)**. KO_ESTIMATED + **`ko_estimation_audit.ko_price` 기록** | audit=이 값 |
| 23:50 | hold_outliers | 16장 carry | 16장 |
| 23:52 | **v6_apply** (`/opt/pokefolio/scripts/v6_apply.py`) | NORMAL=`jp×choose()비율(~0.24)` + MANUAL_ANCHOR/FLOOR + EN→JP브릿지. **down-only** | 대량 |
| 23:55 | sanity_cap (`sanity_cap_extreme_daily.sh`) | `ko > LEAST(jp×jp_p75, en×en_p75)×3`이면 cap. AR en_p75=0.114 | 대량 |

- **audit(stage2)는 디버그값일 뿐, 복구 기준 아님.** live는 overlay 거친 최종값. 둘이 다른 건 정상.
- 고라파덕 추적: 23:45 모델이 spread가드로 EN선택 → audit 57,490 → 23:52 v6가 jp×0.242 → **live 8,000**.

### 2. AR 모델 계수가 2~4.6배 과대 (진짜 버그)
관측 KO/JP·KO/EN (DAANGN VALID, 180일):
| rarity | 총 | 관측n | 관측 KO/JP | 관측 KO/EN | 모델 JP계수 | 과대 |
|---|---|---|---|---|---|---|
| **AR** | 522 | 29(5.6%) | **0.263** | 0.075 | 0.536 | 2.0× |
| SAR | 237 | 72 | 0.307 | 0.175 | 0.377 | 1.2× |
| SR | 1002 | 60 | 0.332 | 0.326 | — | — |
- **모델 EN계수 0.347은 4.6배 과대.** EN은 rarity마다 0.075~0.56로 중구난방 = **EN은 KO anchor 자격 없음.** JP가 anchor.
- **커버리지 2~6% = 카탈로그 90%+가 예상가치.** 계수가 잘 팔리는 소수로 fit → 안 팔리는 다수에 과대적용 (selection bias).

### 3. 번장 실거래 ground truth (6장, 호가 soft signal 포함)
정책: **체결가=hard anchor / 정상 낮은 호가=soft / PSA·BGS·등급용·묶음·일판·영판·삽니다·최고가호가·KREAM 제외.**
| 카드 | card_id | 세트/번호 | JP(KRW) | live | 실거래/판정 | **함의 KO/JP** |
|---|---|---|---|---|---|---|
| 이슬의 고라파덕 | CRD_2284D5AE23CD4A559E27 | sv9a 071/063 | 65,445 | 18,750 | 체결6,300+호가10~15k → **8,500** | 0.10~0.15 |
| 잉어킹 | CRD_053F45EBABE44DD09C9B | 080/073 | 262,833 | 40,750 | DAANGN8+호가42~55k → **40,750 유지** | 0.155 |
| 두빅굴 | CRD_157F33DF43A34D268793 | 확장 109/086 | 106,671 | 30,253 | 호가23~28k → **27,000** | 0.253 |
| 피카츄 | CRD_B56B12EB53F4412BA2DA | 소드실드 205/172 | 287,094 | 9,602 | 호가100k 1건뿐 → **REVIEW/수동앵커 46~50k** | (체이스, 저평가) |
| 이상해씨 | CRD_C9F48C426CE14CFFA191 | 스페셜덱 050/049 | (JP없음) | 24,010 | → **18,000** | KO/EN 0.086 |
| 꼬부기 | CRD_A433CDC6DC8849CEA90A | 스페셜덱 052/049 | (JP없음) | 21,700 | → **16,000** | KO/EN 0.084 |
- **실측 AR KO/JP 중심 ≈ 0.15~0.18** (가장 탄탄한 잉어킹·고라파덕이 0.15~0.16). EN-only는 KO/EN ≈ **0.085** (이상해씨·꼬부기 일치).
- **★구조 인사이트: 체이스라서 KO/JP 비율이 높은 게 아니라, JP raw가 이미 체이스 프리미엄을 먹었다** (잉어킹 0.155 = 고라파덕과 동일). → **4-세그먼트 불필요.** 단일 낮은 계수 + DAANGN/anchor 예외면 충분.

### 4. DRY_RUN 결과 (0.16/0.17, down-only, read-only)
```
AR 522장 │ 0.16: 491장↓ / 0.17: 491장↓ │ DAANGN보호 29 │ EN-only 21 │ 상향차단 2 │ 50%↓크러시 0
median 1,940 → 0.16=1,110(-43%) / 0.17=1,175(-39%)   (0.16≈0.17, 거의 동일)
```
- **진짜 결정은 0.16 vs 0.17이 아니라 "0.24→0.16대로 내리느냐" = 카탈로그 -43%.** 안전(크러시0·DAANGN보호·상향차단)하고 ground truth가 지지(찌르꼬 obscure AR 1,300 < 현 median 1,940).
- 잔여 리스크: **obscure tail(491장 대부분) ground truth = 찌르꼬 1장뿐.** mid/high 6장은 탄탄.

---

## 📐 확정 정책 (Codex 사전리뷰 후 적용)

```
AR JP계수: 0.16 우선 (비교 0.17). 기존 0.263 폐기, 0.536 명백 과대.
EN-only fallback: EN_KRW × 0.085 + 저신뢰 플래그 + 상향금지
DAANGN obs 있으면: DAANGN live 우선 (계수 override 금지)
체이스 thin-data(피카츄 205 등): MANUAL_ANCHOR, 체결 확정 후 숫자
전부 down-only. 자동 상향 금지.
spread가드(GlobalPriceService:2297): JP 있으면 EN으로 안 뒤집기 (EN은 JP없을 때만)
```

### 🚧 절대 가드레일
- **price_snapshots 직접 UPDATE 금지.** 그날 밤 cron이 덮음(= 최초 진단한 그 함정). 반드시 **`ko_price_coefficients` / `v6_apply.py` MANUAL_ANCHOR**로만 재현가능하게 반영.
- prod write = 백업+diff+롤백+사용자 명시OK. 점검토글=사용자만. SSH mutate 출력 `|head` 금지(tail).
- 작업은 **Codex 사전·사후 리뷰** (model-blocked면 `codex:codex-rescue`).

### 카드별 최종값 (TIER 1, 6장)
| 카드 | 처리 |
|---|---|
| 이슬의 고라파덕 071/063 | 18,750 → **8,500** |
| 잉어킹 080/073 | **40,750 유지** (DAANGN8). 69,130 자동상향 금지 |
| 두빅굴 109/086 | **27,000~28,000** (소폭 하향) |
| 피카츄 205/172 | **REVIEW/저신뢰.** 자동상향 금지, 수동앵커 후보 46~50k, 80k 금지 |
| 이상해씨 050/049 | **18,000** (EN-only 저신뢰) |
| 꼬부기 052/049 | **16,000** (EN-only 저신뢰) |
- 무시: 파라스 207/172 (JP $18=노이즈, live 1,649 맞음, down-only가 차단 = 정책 검증) + MEGA드림193 commons 16장(flat).

---

## ▶️ 다음 액션 순서
1. **(이 문서 갱신 = 완료)**
2. **중간대 AR 체결 3~5장 더** (JP $30~70대) → 0.16 vs 0.17 확정 + obscure tail 검증.
3. **Codex 사전리뷰**: 위 정책 + DRY_RUN 영향표.
4. 적용: `ko_price_coefficients` AR JP 0.536→0.16(or 0.17) + EN fallback 0.085 + 피카츄 MANUAL_ANCHOR. spread가드 fix는 별도 BE 배포.
5. sanity_cap AR en_p75=0.114 재평가/폐기 (모델 내려가면 역할 끝, 원래 D-5 임시).
6. SAR(1.2× 경미) 등 타 rarity는 별도 후속.

---

## 🔬 구현 검증 (2026-06-16 B-안전형, prod write 0건)

### 레버 확정 (BLEND 비-이슈)
- `ko_price_coefficients` 컬럼 = `scope/rarity/era/coef_type/coef/active`. **batch_id 버전드** (active unique). 변경 = 신규 batch_id active row insert + 기존 deactivate (raw UPDATE 말고 버전 패턴).
- AR RARITY 활성: JP **0.535789**(s77) / EN 0.366732(s100) / BLEND 0.369643(s78). **BLEND는 `resolveCoeff`가 안 읽음(jp_/en_ 키만)=비-이슈 확정.**
- **레버 = RARITY AR JP 0.535789→0.16** (audit+live 동시 교정, landmine 제거). EN-only = RARITY AR EN 0.366732→**0.085** (spread가드 fix 후 JP없는 카드만 타격).

### CARD-scope AR = **5장**(9 아님), 변경 제외 + 방향 검증
| 카드 | CARD JP계수 | 판정 |
|---|---|---|
| 두빅굴 109/086 | **0.252** | 이미 손튜닝=현실(rec27k) 일치 ✓ 유지 |
| 잉어킹 080/073 | **0.203** | 이미 손튜닝=현실 일치 ✓ 유지 |
| 뮤츠 183/165 | 0.418 | stale 의심 → 리뷰 |
| N의레시라무 109/100 | 0.520 | rarity복붙 stale → 리뷰 |
| 민화의덩쿠리 743/742 | EN-only | — |
- ★두빅굴·잉어킹이 이미 0.2~0.25로 내려가 있음 = "AR 실비율 ~0.2"가 코드에 이미 증거. card-scope는 rarity 변경에서 자동 제외(코드 2676행 cardCoef 우선).

### EN-only 0.085 vs 0.10 → **0.085 채택**
- 이상해씨 050/049 f085 17,880(rec 18k ✓) · 꼬부기 052/049 f085 16,290(rec 16k ✓). 0.10은 과대(21k/19k). tail 차이 <500원.
- 단 파이리 051/049·고우스트 022/021(중간 인기 EN-only)은 REVIEW.

### 캐시 = 미해결 (pre-rollout 必)
- `PriceService.getSummaries()` @Cacheable 아님. 단 **price_summary는 price_snapshots와 별개 테이블** + `CacheConfig @EnableCaching` 존재. **KO_ESTIMATED가 앱에 닿는 경로(직접 read vs price_summary 파생) 추적 후 evict/rebuild 경로 확정해야.**

### 가드 재확인
- holder `purchase_price` 안 건드림(등록시점 기록=위조 금지, UI공지+confidence게이팅으로). price_snapshots 직접 UPDATE 금지. 변경은 `ko_price_coefficients`(버전드)+`v6_apply.py` MANUAL_ANCHOR만.

### prod 변경 DIFF (승인 전)
| # | 대상 | FROM | TO |
|---|---|---|---|
| 1 | coef RARITY AR JP | 0.535789 | 0.16 |
| 2 | coef RARITY AR EN | 0.366732 | 0.085 |
| 3 | GlobalPriceService:2297 spread가드 | JP→EN flip | JP있으면 JP고정 |
| 4 | v6_apply 피카츄205/172 | 없음 | MANUAL_ANCHOR REVIEW |
| — | BLEND·card-scope5·holder pp·price_snapshots | 무변경 | — |

### pre-rollout 잔여 (write 전 클리어)
1. 캐시/price_summary 경로 추적 → evict or rebuild 단계 확정
2. spread가드 코드 수정 + 추가 DRY_RUN (spread fix 반영 영향)
3. coef 버전드 insert 스크립트 (batch_id 패턴)
4. 뮤츠·N레시라무 card-scope + 파이리·고우스트 EN-only REVIEW
5. 최종 diff 표 사용자 승인 → 점검토글(사용자) → 적용

## 🧾 전체 카탈로그 전수조사 (2026-06-16, 3,711장, read-only)

> AR만 보면 안 된다 → 전 rarity 건강검진. 결론: **시세 전면붕괴 아님. 계수 과대는 3개 rarity 집중, 나머지 건강.**

### A. 앱 표시 진실원 + 캐시 (해결)
- 현재가/차트 = `GlobalPriceService.getCardPriceSummary()` (1794행) 즉석계산(KO_ESTIMATED+계수+90일). **`@Cacheable("cardPriceSummary")` Caffeine, TTL 30분, maxSize 4000, @CacheEvict 없음.**
- → **계수 변경 ≤30분 내 앱 반영(TTL 자가만료). 블로커 아님, 타이밍 노트.** 즉시 원하면 재시작/수동 evict.
- `price_summaries`(복수) 테이블 = 실거래 median/avg/trade_count 집계, sparse(고라파덕 0행), **현재가 경로 아님.**

### B. 계수 과대 = 3개 rarity 집중 (audit≥2×live 기준)
| rarity | audit≥2×live | 노출 | 판정 |
|---|---|---|---|
| CHR | **54/54 (100%)** | ✅ | ★새발견. JP1.12/EN1.03(KO>JP 불가) |
| AR | 356/522 (68%) | ✅ | 알던 것 |
| S/K | 127/258·— | ❌ is_visible=false 숨김 | 비노출 후순위 |
| SR·RR·SAR·HR·UR·SSR·RRR·PR·CSR·bulk | 5~19% | ✅ | **정상, 손대지 마** |
- **유저 노출 계수문제 = AR + CHR 둘.** TOTAL: live_med 2,060 · audit≥2×live **726장(landmine 맵, 복구금지)** · DAANGN 243 · card-scope 29 · 오늘밤 sanity 발동 9장뿐.

### C. status 맵 (rarity 레벨)
- WRONG_AT_SOURCE(계수과대·live는 overlay로 OK·audit는 landmine): **AR, CHR**
- LANDMINE(복구금지): audit≥2×live 726장
- OK_NOW(손대지 마): SR/RR/SAR/HR/UR/SSR/RRR/PR/CSR/bulk
- PROTECTED: DAANGN 243·card-scope 29·MANUAL_ANCHOR 17
- STALE: 차트캐시 30분 TTL

### D. 재정의된 결론
"전체 붕괴"가 아니라 **AR+CHR 계수 과대 + 그게 audit에 박혀 726 landmine + 차트캐시 30분 staleness.** 나머지 카탈로그 건강. → 작업 = AR+CHR 계수 재보정(각자 ground truth) + 726 복구금지 명문화 + 차트캐시 타이밍. **CHR은 AR과 별도 ground truth(번장) 필요.**

## 🏗️ 배포/소스 인프라 (2026-06-16 확정 — ★prod git pull/reset 절대 금지)
- **prod 소스 = `/opt/pokefolio/app`** (git `integ/prod-consolidated` @ `060c7416`, **DIRTY working tree**). 현재 back 이미지(6/16 03:13 빌드, 컨테이너 06:26 시작)는 **이 dirty tree로 빌드됨** = 운영 진실원은 commit이 아니라 **working tree**.
- dirty 6파일(246+/68-): GlobalPriceService.java·PriceSyncScheduler.java·AdminController·CardRepository·CardServiceImpl·scanner/main.py. **백업: prod `/home/ubuntu/prod_backups/prod_dirty_20260616.diff` + 로컬 `docs/prod_dirty_worktree_20260616.diff`.**
- ★**prod `/opt/pokefolio/app`에서 `git pull/checkout/reset` 절대 금지** → 미커밋 운영변경 소실=회귀사고.
- **로컬 repo == prod 소스 확인됨**(GlobalPriceService/PriceSyncScheduler md5 일치) → Java 수정은 로컬에서 개발 가능, prod와 동일.
- **수정 방식 맵**:
  - host **in-place 편집 OK**: `sanity_cap_extreme_daily.sh`·`hold_outliers_daily.sh`·`v6_apply.py` (`/opt/pokefolio/cron`·`/scripts`). ← P0가 이 방식.
  - **baked = 소스편집+rebuild+redeploy 필수**: `recalc_coefficients.py`·`calc_ko_coefficients_v1.py`(`/app/python`, config.py만 ro마운트), **모든 Java**. 컨테이너 직접수정=재배포시 소실.
- **빌드/배포**: `docker compose -f /opt/pokefolio/app/docker-compose.prod.yml build back && up -d back` (context `.`, back/Dockerfile). 배포런북(점검토글·백업·healthy·캐시evict) 적용.
- **spread가드**(`GlobalPriceService.selectScrydexSnapshotForKo` ~line 2300, `SPREAD_BASE`)는 **dirty 아님=committed=배포본** → P3는 안정 코드 위 작업.

## 📋 핵심 사실/ID
- **DB**: prod `52.78.3.120`, `docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db`. SSH key `/Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem`. FX usd≈1517.
- **스크립트**: `/opt/pokefolio/scripts/v6_apply.py` (23:52), `/opt/pokefolio/cron/sanity_cap_extreme_daily.sh`(23:55), `hold_outliers_daily.sh`(23:50). 모델 23:45 = Java @Scheduled. python은 back 컨테이너 전용.
- **MANUAL_ANCHOR**: v6_apply.py 상단 17장 (전부 SAR/MUR/HR/SR — **AR 0장**, 그래서 AR 재보정이 anchor 안 건드림).
- **계수표 `ko_price_coefficients`**: scope RARITY/CARD, coef_type EN/JP/BLEND, is_active. AR active = EN 0.366732 / JP 0.535789.
- **audit `ko_estimation_audit`**: `ko_price`(stage2값 독립저장) + selected_source + coef_value 등. 복구기준 아님, 디버그용.
- **이번 세션 prod 변경 = 0건** (전부 SELECT/cat). 환환 pp 1건도 미변경 상태(원래 56,849→8,000 했던 것 — 071/063 8,500 확정 시 재정정 대상).
