# 시세 frozen 계수 재캘리브레이션 런북 (월1회 수동)

> 결정: 2026-06-17. 사용자 선택 = **월1회 수동 재캘리** (sticky-auto 자동화는 백로그).
> 관련 메모리: `project_price_recovery_20260616`.

## 왜 필요한가
`/opt/pokefolio/scripts/v6_apply.py` 의 비율(RRH/GHIT/TIERR/RTR/PRTR + 카드별 DAANGN `ko_vals` 226장)
+ `GlobalPriceService.FROZEN_GLOBAL_COEFFICIENT(0.478)` 는 **2026-06-14 값으로 정적 freeze**됨.
- 이유: DAANGN obs 가 90일 롤링 윈도우에서 노화/만료되면 매일 재계산 시 비율이 절벽처럼 떨어짐(시장 무관 인공물). → 동결로 차단.
- 부작용: **정적이라 시간이 지나면 실제 시장과 괴리** (이력상 ~7%/3주 드리프트). → 주기적으로 새 healthy 날짜의 값으로 재캡처해야 함.

## 주기
- **매월 1회** (리마인더 cron). DAANGN 대량 수집/시장 급변 직후엔 수시.

## 절차 (~30분, prod, 점검 토글은 사용자)

### 0. healthy 기준일 선정
- 최근 시세 사고/폭등 없는 안정일을 고른다 (보통 **오늘 −2~3일**).
- `price_snapshots` / `ko_estimation_audit` 로 그 날짜에 이상 없는지 확인.
- 이하 `REFDATE` = 그 날짜 (`YYYY-MM-DD`).

### 1. v6_apply.py FROZEN_* 재생성
2026-06-17 세션에서 쓴 빌드 패턴 (memory `project_price_recovery_20260616` + 세션 jsonl 참조):
- **head**: v6_src 의 비율 계산부(~GHIT 줄)를 `REFDATE`로 date-patch
  (`traded_at>=DATE 'REFDATE'-90 AND traded_at<DATE 'REFDATE'+1`, `CURRENT_DATE→DATE 'REFDATE'`).
- **tail**: 계산된 RRH/GHIT/TIERR/RTR/PRTR + `ko_vals` 전 카드를 `FROZEN_*` 상수로 주입,
  `choose()`/`ko_vals()` 를 frozen 우선 반환으로 override.
- 산출 = 새 `v6_frozen.py`.
- **백업**: `sudo cp /opt/pokefolio/scripts/v6_apply.py /opt/pokefolio/scripts/v6_apply.py.bak_pre_recal_YYYYMMDD`
- **DRY_RUN 검증** (컨테이너): `docker exec -e DRY_RUN=1 pokefolio-back python3 /tmp/v6_frozen.py`
  → up < 게이트(50), 폭락(crash) 0, MANUAL_ANCHOR 생존, 메가망나뇽/피카츄 등 정상.
- 통과 시 `sudo cp` 로 `/opt/pokefolio/scripts/v6_apply.py` 교체.

### 2. 글로벌계수 갱신 (필요 시)
- `REFDATE` 의 `ko_market_coefficient` SYSTEM 값 확인.
- 드리프트 크면 `GlobalPriceService.FROZEN_GLOBAL_COEFFICIENT` 갱신 → BE 재빌드+`up -d back`.
- 작으면 스킵 가능(글로벌계수는 v6가 23:52 덮어 deep-fallback만 영향).

### 3. 검증
- cron 방식 DRY_RUN (배포 파일을 cp+exec): `up<50 / ABORT 0`.
- 샘플 카드 + 차트 매끈 확인.

## 불변식 (재캘리해도 지킴)
- **down-only 우선**, up 은 게이트(50) + MANUAL_ANCHOR 만.
- **`price_snapshots` 직접 UPDATE 금지** (밤 cron 이 덮음) — `v6_apply.py` / `MANUAL_ANCHOR` 로만 반영.
- **MANUAL_ANCHOR (사용자 확정값)** 은 재캘리해도 유지 (피카츄 71,520 등).
- 백업 + DRY_RUN 통과 전 배포 금지.

## 롤백
- v6: `sudo cp v6_apply.py.bak_pre_recal_YYYYMMDD v6_apply.py` → 재적용.
- 글로벌계수: 이전 상수로 되돌려 BE 재빌드.
