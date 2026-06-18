# 시세 재보정 핸드오프 — 2026-06-16 (v2, 진단 전면 교체)

> **다음 세션 시작점.** 이 문서의 v1(audit 복구 전제)은 **틀렸고 폐기됨.** 아래가 검증된 새 진단.
> 핵심 한 줄: **AR live 가격은 이미 대체로 맞다. 망가진 건 base 모델 계수(2~4.6배 과대)와 audit. 복구가 아니라 "모델 계수 재보정"이 답.**

---

## 🟢🟢 2026-06-16 저녁 — P5 동기화 안정화 **배포 LIVE** (시세값 0건 변경)

> **시세 산식 무관 = "동기화쪽"만.** 밤 sync(@Scheduled 23:45 `refreshKoEstimatesFromSnapshots`)가 6/15처럼 부분실패(후보 ~3700장인데 4장만 저장)해도 **silent 덮어쓰기 차단**하도록 가드 추가 + 낮에 미리 검증할 dry-run 모드. **P3/spread/ratio/계수 일절 무변경**(isolated diff "spread/P3 0건" + Codex 사전검토 GO).

### 배포 내용 (back 이미지 rebuild+redeploy, Java 2파일)
- **P5 부분실패 가드**: build 결과 `allIds≥1000 && snapshots<allIds×0.5`면 **delete/save/audit ABORT + 기존 KO_ESTIMATED 보존**(6/15 4장 silent write 차단). 정상 풀run이면 통과=무변경.
- **입력검증 A**: FX(usd/jpy)≤0 또는 GLOBAL계수≤0 → `aborted_bad_input` early return(write 0).
- **입력검증 B**: rarity 계수맵 비면 → `aborted_empty_coef` early return.
- **full dry-run 모드**: `refreshKoEstimatesFromSnapshots(boolean dryRun)` 오버로드. 실제 nightly와 **동일 경로**(allIds/coef/buildKo) 돌리고 write(delete/save/audit/promo)만 스킵. **no-arg=기존(dryRun=false)→nightly 무변경**(@Scheduled는 no-arg 호출).
- **admin endpoint**: `POST /api/internal/admin/dry-run-ko-estimates` (`InternalAdminController`, InternalTokenFilter `X-Internal-Admin-Token`, nginx 외부차단).

### dry-run 검증 결과 (2026-06-16 19:37, 오늘 prod 실데이터·실제 nightly 경로)
```
status: dry_run_ok / allIds 3748 / wouldSaveCount 3748 / wouldAuditCount 3748 / enSource 3652 / jpSource 3503
write-0 증명: KO_today / audit_today / coef_today = 0/0/0 (전) == 0/0/0 (후)
```
→ **오늘밤 23:45 sync는 3748장 풀세트 정상 산출 예상. 6/15 부분실패(4장) 재현 안 됨.** (수동 actual refresh 안 돌림 = 오늘밤 scheduled run으로 확인이 깔끔, 급하지 않음.)

### ✅✅ 실측 확인 (2026-06-16 23:45 본run — 트래커 실시간 추격, **종결**)
- **23:45:07** `[KoEstimated] refresh 완료: 3749장(모델 3748 + KREAM promo 1), audit 3748, ABORT 0`. 폴링: 23:43~44 KO=0 → **23:45:10 KO=3749**. 6/15 부분실패(4장) 재현 안 됨.
- **23:52 v6_apply**: changed 2456 (**down 2418 / up 38** = down-only 압도), 롤백백업 `ko_v6enbr_rollback_20260616`, anchors 18(MANUAL_ANCHOR 15+HOLD 2+FLOOR 1) 적용. source breakdown 정상(RATIO 2154·NORMAL_HELD 1028·EN_BRIDGE 190·HIT_* 등).
- **23:55 sanity**: 모야모 SAR ~148K 6장 등 P0 18앵커 **생존**(안 깎임).
- **최종 23:57**: count 3749 / audit 3748 / ABORT 0 / min 41 / max 5,612,789 / avg 21,694.
- max tail(5.6M~3.1M) = 판초·고꼬 피카츄 등 **아이코닉 PR(프로모), KO=JP raw 1:1** = 프로모 정책 그대로(글리치 아님, P5/P2 무관).
- **→ dry-run 예측(3748) = 실측(3749) 일치. P5 동기화 안정화 검증 완료·종결. 다음 트랙 = P2 등급계수 정화.**

### ▶ 오늘밤 23:45+ 모니터링 체크리스트 (참고용 — 위에서 이미 실측 확인됨)
```bash
SSH=/Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem; H=ubuntu@52.78.3.120
RUN_DATE=2026-06-16   # ★날짜 고정. 내일 아침엔 CURRENT_DATE=6/17이라 6/16밤 배치를 0건 오판함. CURRENT_DATE 쓰지 말 것.
LOG_DATE=20260616
# 1. KO_ESTIMATED count (~3748 기대, <1874이면 부분실패)
ssh -i $SSH $H "docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c \"SELECT count(*) FROM price_snapshots WHERE source='KO_ESTIMATED' AND traded_at::date='${RUN_DATE}';\""
# 2. audit count (~3748 기대)
ssh -i $SSH $H "docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c \"SELECT count(*) FROM ko_estimation_audit WHERE estimated_date='${RUN_DATE}';\""
# 3. ★ABORT/입력실패 로그 없는지 (있으면 가드가 부분실패 차단한 것 = 입력 원인 조사)
ssh -i $SSH $H "docker logs pokefolio-back 2>&1 | grep -E 'ABORT 부분실패|aborted_bad_input|aborted_empty_coef|KoEstimated' | tail -40"
# 4. v6_apply 정상 완료 (23:52)
ssh -i $SSH $H "tail -80 /opt/pokefolio/data/logs/v6_apply_${LOG_DATE}.log"
# ※ ①②가 0이면 자정 넘겨 찍혔을 수 있음 → RUN_DATE=2026-06-17 로 1회 더 확인 후 판정
```
**판정**: ①②~3748 + ③ABORT없음 + ④정상완료 = **동기화 종결**. ①②적고 ③ABORT있음 = 입력 깨짐(가드 정상작동, FX/계수 조사). ①②적은데 ③ABORT없음 = 가드 임계(0.5) 미달, 재검토.

### 배포 인프라 / 롤백 / dirty
- 패치 2파일 md5 **로컬==prod 일치 확인**: `GlobalPriceService.java`(P5+검증A/B+dryRun 오버로드) + `InternalAdminController.java`(dry-run endpoint).
- **prod working-tree 이제 이 패치로도 dirty(미커밋)** — 기존 dirty(§배포/소스 인프라)에 누적. ★`git pull/reset/checkout` 절대 금지(패치 소실=회귀).
- **백업**: prod `*.bak_p5dryrun_20260616`(두 파일). **롤백 이미지**: `30b4d862`. 롤백 = bak 복원 → rebuild → up -d back.
- 배포 검증: back **HEALTHY(21s)**, Tomcat 정상, exception 0. 재시작=캐시 클리어만(같은 데이터 재계산=같은 값).

### ⚠️ 작업 종료 시 후속
- **★INTERNAL_ADMIN_TOKEN 교체 필요**: dry-run 검증 중 토큰(`e6137864…`)이 대화/로그에 노출. nginx 외부차단이라 외부 악용 위험 낮으나 위생상 교체 권장. 방법: `.env.prod` `INTERNAL_ADMIN_TOKEN` 신규값 → `docker compose up -d back` 1회(restart). 긴급도 낮음, 내부전용.
- 다음 트랙: 오늘밤 sync 정상 확인 후 **P2 등급별 계수 정화**(AR/HR=DAANGN, CHR 수동, SAR/UR 유지). P3/spread는 P2와 함께만(`docs/PRICE_P3_P5_PATCHES_HOLD.md`).

---

## 🔴 2026-06-17 00시 — 6/16 시세 폭등 26장 긴급 교정 (스톱갭, ★재발예정)

> **6/16 본run이 26장을 3~8배 폭등시킴**(6/12~14 안정 → 6/16만 튐 = 회귀). 점검 ON 상태 + 사용자 명시승인("우리끼리") 하에 **price_snapshots 직접 UPDATE 철칙 일회 예외**(백업·검증·캐시클리어 완료).

### 증상/근본원인
- **증상**: 이브이 AR 15,598→46,129, 로켓단뮤츠ex 52,000→90,710, 뮤츠&뮤 8,877→38,531, 리자몽EX PR 2,205→17,485 등 **26장**. 3일(6/12~14) 안정 baseline이 회귀 증명.
- **근본**: base 모델이 EN-spread로 부풀림(이브이 AR: EN136,300×en_AR0.3356=46,129 / JP면 66,413×0.3749=24,898). **평소엔 v6_apply가 jp×ratio(~0.235)로 깎는데(6/14: 47,450→15,598), 6/16엔 v6가 이 16장을 candidate에서 스킵**(26장 중 v6백업 `ko_v6enbr_rollback_20260616`에 10장만 존재·이브이AR 등 16장 미존재) → **6/15 사고대응으로 v6_apply.py 수정(gate/UP_GATE)한 게 categorization 바꿔 held로 빠뜨린 v6 회귀**. P5 sync 무관, 값/오버레이 문제. (14장=base JP→EN flip[spread guard], 나머지=base EN인데 v6 미교정)

### 교정 (prod 적용 완료)
- 26장의 **6/16 KO_ESTIMATED price → 각자 6/14 안정값으로 UPDATE**(전부 down-only). 백업 `ko_spike_fix_backup_20260616`(card_id/old_price/new_price). back 재시작=cardPriceSummary 캐시 클리어. 점검 OFF=사용자.
- **롤백**: `UPDATE price_snapshots ps SET price=bk.old_price FROM ko_spike_fix_backup_20260616 bk WHERE ps.card_id=bk.card_id AND ps.source='KO_ESTIMATED' AND ps.traded_at::date='2026-06-16';`

### ★★ 재발 경고 (반드시 6/17 23:45 전 처리)
- **데이터 스톱갭일 뿐 — 근본 v6_apply.py 회귀는 안 고침.** 내일(6/17) 23:45 본run+v6 돌면 **같은 16장 또 스킵→재폭등.**
- **다음(6/17 낮) 할 일**: 컨테이너 `/tmp/v6_apply.py`(또는 `/opt/pokefolio/scripts`) categorization 읽어 "jp 있는데 왜 이브이AR 등이 RATIO 아닌 NORMAL_HELD/KEEP로 빠지나" 핀포인트 → held 버그 수정 → Codex 리뷰 → 승인. 안 고치면 매일밤 스톱갭 반복.

## 🔬 6/16 폭등 26장 — v6 decision trace 확정 (2026-06-17, 추측 아님)

> **방법**: live `v6_apply.py` 안 건드리고 복사본 `/tmp/v6_trace.py`에 같은 함수/데이터, curv를 `ko_estimation_audit.ko_price`(6/16 base)로 복원해 23:52 재현. 26장 전부 실제 decide() 통과.

### 결정 분류 (FINAL=v6가 산출했을 값, 현재 live는 스톱갭으로 6/14값)
| 버킷 | n | 대표(curv→FINAL) | 원인 |
|---|---|---|---|
| **NORMAL_HELD** | 14 | 뮤츠&뮤 38,531(ratio_px 56,630)·N의각오 31,339·자시안 UR 24,083·리자몽EX PR 17,485·피카츄 PR 5,272(rpx 22,830) | **`jp×r > curv` (r 과대: SR 0.5·PR 0.693·UR 0.875)** → down-only가 "내림" 아닌 "올림"으로 봐서 보류 |
| **RATIO(but 높음)** | 9 | 로켓단뮤츠 SAR 155,744→90,710(6/14 52,000)·그루샤 17,870·M전룡 12,380·매시붕 2,870(6/14 810) | v6가 내리긴 함, **but r 과대(SAR 0.319 등)라 결과가 6/14보다 높음** |
| **KEEP_CHASE** | 1 | **이브이 AR 46,129** (ratio_px 10,550 가용·r 0.159 정확) | `이브이+AR+base≥20K` 하드코딩→NORMAL_CHASE→DAANGN없음→KEEP_CHASE. **올바른 하향(10,550)을 chase가드가 차단** |
| CORRUPT_JP_BRIDGE | 1 | 고릴타 UR 7,980 | jp 맵에 없음(raw KRW) → EN 브릿지 |
| KEEP_REVIEW | 1 | 빼미스로우 S 2,323 | FORCE_REVIEW 리스트 |

### ★ 근본 = 3겹 (전부 P2/P3, 우리 P5/P0 무죄)
1. **base EN flip (P3)**: 14장 audit s14=JP→s16=EN. 6/16 EN/JP raw 관계 shift로 스프레드가드가 EN 선택 → base 폭등. (뮤츠&뮤 base 6/14 JP 8,877 → 6/16 EN 38,531)
2. **v6 비율 r 과대 (P2)**: SR 0.5/PR 0.693/UR 0.875 = 실측(~0.16~0.25)의 2~6배 → `jp×r > 부풀린 base` → down-only 무력(NORMAL_HELD). RATIO 카드도 결과가 여전히 높음.
3. **이브이 chase 백파이어 (v6)**: chase 보호가 올바른 하향까지 막음.
- ★**파이프라인에 일반 급등 가드 없음**: hold_outliers=하드코딩 16장 전용(우리26장 무관), sanity=p75×3(SR/PR 임계 너무 높아 못잡음·AR만 칼날). v6 통과하면 끝.
- ★**우리 변경 무죄 단, v6_apply.py는 6/16 새벽(02:03/06:21, 이전세션 UP_GATE+anchor17) 변경이력 있음 — gate수정이 직접원인은 아니나(categorization 불변) 운영변화 타이밍으로 기록.**

### 재발방지 설계 — ★전체 3749장 full dry-run으로 확정 (2026-06-17, Codex 검토 대기·미적용)
> 26장 trace=원인분석용. 패치검증=**전체 후보 3710장 패치전/후 비교** + false-positive 점검(앵커/프로모/DAANGN/정상고가). live 안 건드림(복사본 `/tmp/v6_fb.py`, rollback).

- **★FIX-A 폐기**: NORMAL_CHASE에 `ratio_px<curv면 하향` 안. dry-run 결과 **망가진 비율(P2)에 의존해 안정 chase까지 과교정** — 리자몽/다크라이 VSTAR(before≈stable인데 반토막)·파이리/꼬부기/이상해씨(stable보다 낮게). **폐기.**
- **★FIX-B 채택 (단독)**: post-v6 **empirical 3일-median 스파이크 hold**. 비율 독립이라 robust.
  ```
  조건: v6결과 > median(최근3 유효 KO일) × 1.5  AND not MANUAL_ANCHOR/FLOOR  AND not DAANGN근거  AND median ≥ 1000
  처리: 그 값 → median  (down-only, reason=SPIKE_HOLD)
  위치: v6_apply.py 끝 또는 23:54 post_v6_spike_guard (v6 이후여야 함=v6가 못 내린 값 잡으려고)
  ```
- **full dry-run 결과(faithful: cko+curv=audit base로 내일 재폭등 재현)**: 변경 **31장·전부 DOWN·전부 SPIKE_HOLD**. 26중 21 + 추가 10(스톱갭서 놓친 부풀이). 이브이 46,129→15,790(=stable, FIX-A 없이 정확)·VSTAR류 제외(스파이크 아님)·파라스→1,649(핸드오프 일치)·앵커/고가프로모/DAANGN 0건. after 전부 ≈ stable.
- ⚠️ 리뷰(배포 막진 않음): 글레이시아 HR·토대부기·마그마번 = JP없고 EN만 높음 → recent stable로 hold. 만성저평가 의심이나 FIX-B가 악화는 안 시킴(3일전값 유지). 진짜값=P2/아이코닉floor 별건.
- **FIX-C (근본, 후순위)**: P2 SR/PR/UR/CHR 비율 정화 → jp×r<base라 v6 자동 하향. + P3 스프레드 JP-first.
- 우선순위: 1️⃣ **FIX-B(단독) Codex검토→승인→6/17 23:45 전 적용** → 2️⃣ P2 비율정화 → 3️⃣ P3. **FIX-B는 임시 안전망, P2/P3 대체 아님.**
- 도구: `/tmp/v6_fb.py`(faithful FIX-B dry-run, 재실행가능). `/tmp/v6_trace.py`(26장 decision trace).

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

## ★★ 계수 store 이중구조 (2026-06-16 정정 — 다음세션 필독, 같은 실수 금지)
- **RARITY 계수(모델 주력) 진짜원 = `price_snapshots` SYSTEM `ko_coef_jp_{rarity}`** (price÷10000). `loadRarityCoefficients()` GlobalPriceService:292. 예: ko_coef_jp_AR=**0.3749**, ko_coef_jp_CHR=**0.9676**, ko_coef_jp_GLOBAL=0.3829. **`recalc_coefficients.py`가 씀.** substrate=NAVER_CAFE+NAVER_OLD+DAANGN(VALID,60d), ×1.12, EN무cap.
- **CARD override = `ko_price_coefficients` 테이블** (scope=CARD, BOOTSTRAP_20260515). `loadCardCoefficients()` :305. **`calc_ko_coefficients_v1.py`가 씀** (substrate=`v_ko_actual_prices` 뷰 = NAVER_OLD+DAANGN+**ko_verified_trades[현재 0행=미가동]**, 1.12없음·EN cap·시간가중).
- **검증 진실원 = `ko_estimation_audit.coef_scope/coef_key/coef_value`** (모델이 실제 적용한 계수 기록).
- ⛔ **`ko_price_coefficients`의 RARITY 행(AR JP 0.535789)만 보고 모델계수 판단 금지** — legacy/미사용. **실제 AR JP=0.3749.** (이번 세션 한참 0.536으로 오판→audit이 진실원).
- 실제 인플레: AR 0.3749/관측0.263 = **1.42×** / CHR 0.9676 = **2.4×**.

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
