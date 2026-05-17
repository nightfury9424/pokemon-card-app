# KO 가격 산출 정책 (2026-05-16 확정)

> 1주일 토론 결과 — Claude + Codex 합의안. 본 문서가 작업/운영 단일 진실원이다.
> 컨텍스트 압축 시에도 이 문서로 정책 복원 가능.
>
> **2026-05-16 구현 완료 (백서버 reboot 대기)**. 작업표 ①~⑦ 종료. 운영 검증 단계 진입.

## TL;DR

```
Phase 0 (substrate 통합 + anomaly filter + 검수 흐름)로 데이터 품질부터 잡고,
그 위에 X (RARITY 주1회 freeze + GLOBAL 매일 7obs median)를 올린다.
shrinkage(Y/Z)는 보류 — Phase 0 정착 후 1~2주 모니터하고 재검토.
```

---

## 1주일 토론 발견 8가지

```
[발견 1] 매일 sync는 6/7단계 정상 작동 (KREAM 메타몽만 5/13 이후 fail)
[발견 2] 계수 cascade = CARD > RARITY > GLOBAL > Java fallback. 실측 91% RARITY hit / 9% GLOBAL fallback
[발견 3] RARITY 매일 갱신 변동성 ±34~48% — SR 989장이 하루 -19% 가능
[발견 4] GLOBAL 단일값이라 일별 ±11% 변동이 318장에 propagate (en이 특히 noisy)
[발견 5] validation_status 컬럼은 schema에 있으나 실제 검수 흐름 부재 (전부 default 'VALID')
[발견 6] recalc_coefficients.py는 검수된 NAVER_CAFE_OLD/DAANGN 1,202건을 무시, raw NAVER_CAFE 448건만 사용
[발견 7] 5/15 jp_SR -19% 원인 = SR 거래 14,000원 입력 오류 1건이 60일 윈도우 IQR 통과해서 median 왜곡
[발견 8] 5장 거래량 top 카드 백테스트: 정상 환경에서 X(36.6% MAE) > Y/Z shrinkage(41.4%/41.2%). 정상 데이터 환경에선 shrinkage가 RARITY signal을 GLOBAL로 끌어가 정확도 손해
```

---

## 최종 정책 12섹션

### 1. 데이터 수집
- **NAVER_CAFE 수집은 매일 유지** (기존 PriceSyncScheduler 22:00 cron)
- **DAANGN은 현재 자동 cron 미존재** → 기존 `DAANGN.VALID` 347건만 substrate에 포함
- DAANGN 신규 수집 자동화는 별도 작업으로 분리 (12-12)
- NAVER_CAFE 신규 수집 데이터는 즉시 계수 산출에 사용하지 않는다
- NAVER_CAFE 신규 수집 데이터 default = `PENDING_REVIEW`
- 명백한 오입력은 anomaly filter가 `INVALID` 자동 분류

### 2. 사용자 검수
- 매주 월요일 03:00 RARITY/CARD 재계산 **전에** PENDING_REVIEW 검수 필수
- 정상 → `VALID`, 오입력 → `INVALID`
- 03:00 전까지 미검수 PENDING은 해당 주 substrate 제외
- 운영 원칙: "수집 매일 / 검수 월 03:00 전 주1회 필수 / 계수 반영은 VALID만"

### 3. 계수 산출 substrate
```sql
source IN ('NAVER_CAFE', 'NAVER_CAFE_OLD', 'DAANGN')
AND validation_status = 'VALID'
```
- NAVER_CAFE_OLD는 기존 정제 데이터로 간주
- PENDING_REVIEW / INVALID는 제외

### 4. anomaly filter (2단계)
**1차 — 수집 시점**:
- `price_naver_cafe.py` 등 수집 단계에서 명백한 오입력 → `INVALID`
- 나머지는 `PENDING_REVIEW`

**2차 — 산출 시점**:
- `recalc_coefficients.py`에서 VALID 데이터에도 ratio guard 재검증
- ratio 기반 guard 우선

**임계값 정책**:
- ratio guard 초기값: `0.05 ≤ NAVER/SCRYDEX ≤ 3.0` (확정값 아님)
- rarity/source별 데이터 분포 확인 후 조정 가능하도록 **상수화** (예: `RATIO_FLOOR`, `RATIO_CEILING`)
- INVALID 처리 시 **`invalid_reason` 필수 기록** (예: `"ratio_out_of_range:0.018"`)
- 하드 삭제 X — 검수 UI에서 사후 review 가능하게
- rarity별 absolute floor는 보조 (명백한 입력 단위 오류 방어용, 예: SR 1만원 미만)

### 5. 계수 cascade — 변경 없음
```
1순위  CARD coef   (현재 32장, 검수 substrate로 누적 보강)
2순위  RARITY coef (월요일 주1회 freeze, raw 그대로 — shrinkage 없음)
3순위  GLOBAL      (매일 7obs median, RAW/SMOOTH 분리)
4순위  Java fallback (변경 없음)
```

### 6. GLOBAL 정책
- 매일 계산
- DB 모델: `ko_coef_jp_GLOBAL_RAW`(신규 substrate) / `ko_coef_jp_GLOBAL`(기존 키, Java가 읽음)
- 기존 키에는 **최근 7개 RAW observation의 median** 저장
- 기준: `ORDER BY traded_at DESC LIMIT 7` (calendar days 아님 — 누락일 영향 차단)
- observation 7개 미만 시 가진 만큼으로 median

### 7. RARITY 정책
- 매일 재계산하지 않음
- 월요일 03:00 주1회만
- raw 값 그대로 freeze (shrinkage 도입 X)
- Phase 0 적용 후 1~2주 모니터 → 여전히 noisy하면 shrinkage 재검토

### 8. CARD coef 정책
- 검수 substrate 기반으로만 보강
- 월요일 03:00 `calc_ko_coefficients_v1.py` 실행
- RARITY 평균 한계 카드(잠만보 -59%, 오리진 디아루가 +35% 등)는 CARD 보강 대상으로 별도 관리

### 9. 운영 cron
**매일**:
- 22:00 **NAVER_CAFE 수집** → `validation_status='PENDING_REVIEW'` INSERT (DAANGN 신규 자동 수집은 이번 작업 범위 제외)
- 23:00 `recalc_coefficients.py --mode global`
- 23:45 KO_ESTIMATED 재계산 (Java, 변경 없음)

**매주 월요일 03:00 전**:
- 사용자 PENDING_REVIEW 검수 완료 (VALID/INVALID 확정)

**매주 월요일 03:00**:
- `recalc_coefficients.py --mode rarity`
- `calc_ko_coefficients_v1.py` (CARD coef 보강)

### 10. backfill (1회)
- 기존 `ko_coef_jp_GLOBAL` / `ko_coef_en_GLOBAL` 시계열 → 각각 `_GLOBAL_RAW`로 복사
- 기존 데이터 삭제 X
- `NOT EXISTS` 조건으로 중복 INSERT 방지

### 11. deploy 직후 RARITY baseline
- `--mode rarity` 바로 write 금지
- 먼저 `--mode rarity --dry-run`으로 jp_SR / jp_SAR / jp_AR / jp_UR 결과 확인
- 5/15 `jp_SR = 0.3189` 같은 noisy 값 재현 시 반영 X
- 정상 범위 확인 후에만 실제 반영
- noisy면 직전 7obs RARITY median을 수동 INSERT로 baseline reset

### 12. 이번 작업에서 제외 (별도 작업으로 분리)
- shrinkage Y/Z 도입
- `ko_price_coefficients(scope=RARITY)` 31건 dead 데이터 정리
- drift monitor (매일 dry-run 비교)
- EMA smoothing (월요일 RARITY 점프 완화)
- KREAM 토큰 갱신 (5/13 이후 fail)
- full 검수 UI 구축 (Spring admin / 별도 FastAPI)
- DAANGN 신규 수집 자동화
- 사용자 검수 자동 알림 (일요일 21:00 cron)
- 잠만보류 outlier 수동 CARD coef 추가

---

## 작업 순서 (2026-05-16 진행)

옵션 1 (단계별 진행) 채택. 검수 UI는 옵션 C (SQL 직접 검수) 즉시 운영 시작.

| 단계 | 작업 | 상태 | 결과 |
|---|---|---|---|
| ① | `recalc_coefficients.py:130` WHERE 절 확장 (substrate 통합) | ✓ | substrate 286→1,121 (3.9배). 응급 정상화: jp_SR 0.3189→0.3742, KO_ESTIMATED 3,709장 재계산 |
| ② | dry-run 검증 | ✓ | SR +17.8%, AR -14.7% 등 계수 변화량과 카드 가격 변화 정확히 일치 |
| 3a | 산출 시점 `RATIO_FLOOR/CEILING` ratio guard (`recalc_coefficients.py:32-33,139-145`) | ✓ | JP RR 0.1916→0.2861 (+49%) outlier 제거, CHR JP cap 통과 |
| 3b | 수집 시점 `validation_status` 분류 (`price_naver_cafe.py`) | ✓ | INSERT default `PENDING_REVIEW`, ratio guard 실패 시 `INVALID + invalid_reason` 자동 |
| 3추가 | 5/15 14,000원 SR 거래 수동 INVALID 처리 | ✓ | `0bacdf131eb240ad98b96b1526e164fd` invalid_reason='manual_review:suspected_input_error_14000' |
| ④ | `--mode global/rarity/both` 분기 + `save_global_coefficients()` / `save_rarity_coefficients()` 분리 | ✓ | GLOBAL RAW/SMOOTH 분리 저장, 7obs median, Java 무변경 |
| ⑤ | backfill SQL dry-run (BEGIN/ROLLBACK) | ✓ | jp 12건 + en 12건 = 24건 시뮬 정상, gen_random_uuid 가용 확인 |
| ⑥ | backfill 실행 + `--mode global` 첫 production | ✓ | _RAW 24건 적층, jp_GLOBAL 0.3932→0.4041 / en_GLOBAL 0.3663→0.3855 (7obs median 적용) |
| ⑦ | `PriceSyncScheduler.java` cron 변경 + `calc_ko_coefficients_v1.py` 이동 | ✓ | `/tmp/` → `python/`, 23:00 `--mode global` / 월 03:00 `--mode rarity + CARD` |
| **백서버 reboot** | Spring Boot 재시작 (cron 코드 반영) | **사용자 대기** | `cd back && ./gradlew bootRun` |
| ⑧ | 다음 월요일(5/18) 03:00 첫 RARITY 자동 사이클 시점 직전 `--mode rarity --dry-run` 검증 | 5/18 직전 | jp_SR / jp_SAR / jp_AR / jp_UR vs 직전 7obs median ±10% 임계 점검 |
| ⑨ | 정상 → 자연 cron 실행 / noisy → 직전 7obs median 수동 INSERT로 baseline reset | 5/18 직전 | — |
| ⑩ | 문서 + 메모리 업데이트 | ✓ | 본 doc + project_ko_price_system.md + project_must_before_deploy.md (보안 메모) |
| ⑪ | 5/18 이후 1~2주 monitor: shrinkage 재검토 trigger 여부 판단 | 운영 | RARITY 일별 변동 ±20%+ 빈발 시 shrinkage(Y) 도입 |

---

## ① 작업 시 Codex 추가 조건

```
1. 기존 NAVER_CAFE.VALID 448건은 그대로 VALID 유지
   신규 INSERT부터 PENDING_REVIEW (③ 단계에서 적용)
   기존 데이터 일괄 PENDING_REVIEW로 reset 금지

2. 변경 전 source별 validation_status 분포 확인
   → 검증 완료 (2026-05-16): 모두 'VALID', NULL 없음. COALESCE 불필요.

3. JP/EN 양쪽 coefficient 산출 쿼리 모두 수정 (_calc_coefficients 함수)

4. ① 단계에서는 WHERE 절 확장만. anomaly filter / freeze 정책은 별도 단계로 분리해서 효과 분리 검증.

5. dry-run 결과 표시 항목:
   - 변경 전 substrate row 수 vs 변경 후
   - jp_GLOBAL / en_GLOBAL 변화
   - jp_SR / jp_SAR / jp_AR / jp_UR 변화
   - en_SR / en_SAR / en_AR / en_UR 변화
   - 5/15 jp_SR 0.3189 완화 여부 (핵심 검증 포인트)

6. DAANGN 자동 cron 부재 확인 완료 (2026-05-16)
   - PriceSyncScheduler.java에 DAANGN 수집 cron 없음
   - 기존 DAANGN.VALID 347건만 substrate에 포함
   - DAANGN 신규 수집 자동화는 별도 작업으로 분리 (12-12)
```

---

## 미시 운영 체크포인트 (정책 변경 X, 인지 사항)

### (1) "매일 GLOBAL"의 실질 변동성
- 매일 산출하지만 substrate가 검수된 데이터로 한정되어 사실상 주1회 변동에 가까울 수 있음
- 매일 cron의 의미는 환율 변동 + 60일 윈도우 슬라이드 정도
- 1~2주 운영 후 "매일 vs 주1회 합치기" 단순화 검토 가능

### (2) 잠만보(-59%) / 오리진 디아루가(+35%) 단기 노출
- Phase 0 + X로 해결 안 됨 (RARITY 평균 한계)
- CARD coef 보강 누적까지 transient
- 임시 대응: 수동 CARD coef 즉시 추가 가능 (별도 작업)

### (3) 사용자 검수 누락 방지
- 자동 알림 부재 시 검수 누락 → 1주 stale
- catastrophic 아니지만 운영 friction
- 일요일 21:00 알림 cron 추가 권장 (별도 작업, 12-12)

### (4) GLOBAL 매일 cron fallback
- substrate sample 부족 시 (MIN_SAMPLES=10 미달) → 해당 rarity skip → GLOBAL fallback
- 기존 동작 그대로 유지

---

## 추후 trigger (메모리 명시 사항)

### shrinkage 재검토 trigger
- Phase 0 deploy 후 1~2주 모니터링
- RARITY 일별 변동이 여전히 ±20%+ 빈발 → shrinkage(Y) 도입 검토
- weight 시작값 0.25 (fixed), 등급별 차등(Z)은 over-engineering으로 분류

### CARD coef 보강 trigger
- 잠만보, 오리진 디아루가, 포켓몬센터 직원 등 RARITY 평균 한계 카드
- 검수 데이터 누적 시 IQR n≥5 통과로 자동 승격
- 매주 월요일 `calc_ko_coefficients_v1.py` 자동 보강

### Phase 2 trigger (memory의 기존 정책 그대로)
- 자체 거래(APP_TRADE) 시스템 출시 후
- EMA α=0.3로 점진 갱신 (사용자 체감 가격 점프 방지)
- source trust weight: APP_TRADE 1.0 / DAANGN 0.7 / NAVER 0.5

---

## 데이터 모델 변경 요약

| 키 | 의미 | 변경 |
|---|---|---|
| `ko_coef_jp_GLOBAL_RAW` / `ko_coef_en_GLOBAL_RAW` | 매일 raw global (substrate) | **신규** |
| `ko_coef_jp_GLOBAL` / `ko_coef_en_GLOBAL` | 매일 7obs median (Java가 읽음) | 값 의미 강화 |
| `ko_coef_jp_SR` / `ko_coef_en_SAR` 등 | 주1회 freeze raw RARITY | 갱신 주기 변경 |
| `price_snapshots.validation_status` | default 'VALID' → 'PENDING_REVIEW' | 흐름 활성화 |
| `ko_price_coefficients(scope=RARITY)` 31건 | dead 데이터 (Java 안 읽음) | **별도 작업으로 정리** |

---

## 백테스트 요약 (5장 거래 top, 정상 freeze 시점)

| 카드 | rarity | 실제 median | X (raw) | Y (shrink 0.25) | Z (AR/UR w=0.5) |
|---|---|---:|---:|---:|---:|
| 성호 메타그로스 ex | SAR | 19,000 | **20,839 (+10%)** | 22,160 (+17%) | 22,160 (+17%) |
| 잠만보 | AR | 23,500 | 9,522 (-59%) | 8,295 (-65%) | 8,705 (-63%) |
| 오리진 디아루가 VSTAR | UR | 35,500 | 47,953 (+35%) | 45,182 (+27%) | 46,113 (+30%) |
| 로켓단의 뮤츠 ex | UR | 28,000 | **22,922 (-18%)** | 21,597 (-23%) | 22,042 (-21%) |
| 포켓몬센터 직원 | SR | 151,500 | 58,452 (-61%) | 37,802 (-75%) | 37,802 (-75%) |
| **평균 MAE%** | | | **36.6%** ★ | 41.4% | 41.2% |

→ 정상 데이터 환경에서 X 우세. shrinkage는 noise 흡수 효과 있으나 정상 signal도 약화. Phase 0로 noise를 입력 단계에서 차단하는 게 정공법.

---

## 관련 문서
- [PRICE.md](PRICE.md) — 기존 시세 시스템 개요
- [ROADMAP.md](ROADMAP.md) — 전체 로드맵
- [REFACTOR_2026-05-12.md](REFACTOR_2026-05-12.md) — 이전 시세 리팩토링
- 메모리 `project_ko_price_system.md` — 본 정책 결정 메모
- 메모리 `project_must_before_deploy.md` §4 — Price admin endpoint 인증 부재 (2026-05-16 발견, 운영 배포 전 필수 처리)

---

## 보안 메모 (운영 배포 전 필수)

**2026-05-16 발견**: `PriceController.java:184` `/api/prices/admin/refresh-ko-estimates` endpoint가 인증 없이 호출됨 (HTTP 200으로 3,709장 KO_ESTIMATED 재계산 트리거 가능). 같은 패턴: `market-adjustment`, `backfill-ko-history`, `refresh-ko-live`, `recalculate-en-jp-ratios` 모두 인증 게이트 부재 추정.

→ `project_must_before_deploy.md` §4에 등록. P0 #1 SecurityConfig 작업 시 함께 처리.
