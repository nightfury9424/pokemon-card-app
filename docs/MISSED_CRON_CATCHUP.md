# MISSED_CRON_CATCHUP.md — 시세 수집 누락 보호 구조 (2026-05-19)

> Spring `@Scheduled`는 misfire instructions가 없다. 서버가 cron 시각에 꺼져 있으면 그 cron은 영원히 놓친다. 본 문서는 누락된 cron을 안전하게 catch-up + retry + 알림하는 구조를 정의한다.

## 배경 — 진단 결과 (2026-05-18 ~ 19)

- **5/17, 5/18 ① SCRYDEX 21:00 cron 2일 연속 미실행**.
- 원인: 서버 가동 시각이 cron 이후 (5/17 22~23시, 5/18 21:52).
- 결과: SCRYDEX_EN/JP 신규 row 5/16 이후 0건 → ⑥ KO_ESTIMATED가 5/16 데이터로 환산.
- `price_scrydex.py`에 dry-run 옵션 없음 (`--backfill --days N`만 있음).
- 매핑 cap은 정상 (cards 9,728장 중 SCRYDEX 매핑 3,690장 = NO_ flag 6,038장 의도된 skip).

## Phase 분할

| Phase | 범위 | 출시 기준 |
|-------|------|----------|
| **1 (필수)** | SCRYDEX_DAILY + REFRESH_KO_ESTIMATED 두 job catch-up | 베타 배포 차단 항목 |
| **2 (1주 후)** | ② NAVER / ③ RECALC_GLOBAL / ⑦ RAW_PSA10 동일 패턴 + 완전 DAG | 안정화 |
| **3 (장기)** | Quartz / db-scheduler / ShedLock 도입 검토 (다중 서버 전환 시) | 운영 성숙 |

## 핵심 원칙 (Codex 권고 + 사용자 보정 수용)

1. **`price_sync_runs.SUCCESS`를 primary source.** 데이터 row 존재는 보조 검증.
2. **`UNIQUE(job_name, business_date)`** + `INSERT ON CONFLICT DO NOTHING`으로 동시성 단일 진실원.
3. **due schedule 기반 businessDate** — `bizDate 21:00 Asia/Seoul` 형태로 명시.
4. **`ZoneId.of("Asia/Seoul")` + `Clock` 명시** (테스트 가능성).
5. **Python 실행은 트랜잭션 밖.** DB 커넥션을 30분 잡지 않는다.
6. **알림은 retry_count >= 3 도달 시 1회만** (`notified_at` 가드).
7. **CRON entry point는 단 하나.** 기존 PriceSyncScheduler 메서드를 `runIfNeeded(CRON)`로 감싼다. 신규 21:00 cron 추가 금지.
8. **Scrydex catch-up 성공 후 KO_ESTIMATED stale 검사** + 연쇄 trigger 필수.
9. **시간 컬럼은 `TIMESTAMPTZ`** (TZ-aware, Asia/Seoul 운영 일관성).
10. **`row_count=0` 시에도 warning 마커 적재** (`error_message='[warn] rowCount=0'` + `log.warn`).

## 테이블 DDL

```sql
CREATE TABLE price_sync_runs (
  id              BIGSERIAL    PRIMARY KEY,
  job_name        VARCHAR(50)  NOT NULL,
  business_date   DATE         NOT NULL,
  status          VARCHAR(20)  NOT NULL,    -- RUNNING / SUCCESS / FAILED / SKIPPED
  trigger_source  VARCHAR(20)  NOT NULL,    -- CRON / STARTUP / WATCHDOG / MANUAL
  scheduled_at    TIMESTAMPTZ  NOT NULL,    -- bizDate 21:00 KST 등 due schedule (TZ-aware)
  started_at      TIMESTAMPTZ  NOT NULL,
  ended_at        TIMESTAMPTZ,
  row_count_en    INTEGER,
  row_count_jp    INTEGER,
  retry_count     INTEGER      NOT NULL DEFAULT 0,
  error_message   TEXT,
  notified_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  UNIQUE (job_name, business_date)
);
CREATE INDEX idx_psr_lookup ON price_sync_runs (business_date, job_name, status);
CREATE INDEX idx_psr_stale  ON price_sync_runs (status, started_at) WHERE status = 'RUNNING';
```

## Phase 1 job 정의

| job_name | scheduled_time (KST) | 의존 |
|----------|---------------------|------|
| `SCRYDEX_DAILY` | 21:00 | — |
| `REFRESH_KO_ESTIMATED` | 23:45 | `SCRYDEX_DAILY` SUCCESS 선행 |

## 서비스 구조

```
[Trigger Layer]
PriceSyncScheduler (기존, 메서드 본체만 수정)
├ @Scheduled(cron="0 0 21 * * *")  syncGlobalPrices()
│   → ScrydexSyncService.runIfNeeded(CRON)        ← runPython 직접호출 제거
└ @Scheduled(cron="0 45 23 * * *") refreshKoEstimates()
    → KoEstimatedSyncService.runIfNeeded(CRON)   ← globalPriceService 직접호출 제거

SyncCatchUp (신규)
├ @EventListener(ApplicationReadyEvent) onReady()
│   → @Async 처리, 두 job runIfNeeded(STARTUP)
└ @Scheduled(fixedDelay=600000)         watchdog()
    → reapStale() + 두 job runIfNeeded(WATCHDOG)
```

## row_count = 0 정책

| job | rowCount=0 처리 | 추가 액션 |
|-----|----------------|----------|
| SCRYDEX_DAILY | **FAILED** | scrydex API 0건은 호출 실패로 간주. retry 흐름 진입 |
| REFRESH_KO_ESTIMATED | **SUCCESS_WITH_WARNING** | row=0이 정상일 수도 있으나 `error_message='[warn] rowCount=0'` 마커 적재 + `log.warn` 출력. 운영자 디버깅 추적용 |

## 검증 기준

| # | 시나리오 | 기대 동작 |
|---|---------|----------|
| 1 | 21:00 정상 가동 | CRON entry → SCRYDEX_DAILY SUCCESS |
| 2 | 21:52 늦은 가동 | STARTUP @Async → bizDate=today → SCRYDEX_DAILY catch-up → KO 연쇄 |
| 3 | 00:30 가동 | STARTUP → bizDate=yesterday → SCRYDEX_DAILY catch-up + KO catch-up |
| 4 | SUCCESS 후 watchdog | SKIPPED |
| 5 | Python exit != 0 | FAILED → 10분 후 watchdog 재시도 (retry++) |
| 6 | retry 3회 모두 실패 | SKIPPED + notifyOpsFailure 1회만 |
| 7 | RUNNING stuck | watchdog reap → FAILED → 재시도 |
| 8 | CRON + STARTUP 같은 시각 | ON CONFLICT — 1개만 RUNNING |
| 9 | SCRYDEX FAILED 상태 | KO_ESTIMATED catch-up SKIPPED |
| 10 | row_count=0 (REFRESH) | SUCCESS + log.warn + error_message 마커 |
| 11 | 로컬 강제 테스트 | `Clock.fixed(bizDate 22:00 KST)` 주입 |

## Phase 1 구현 단계

1. `back/sql/price_sync_runs_migration.sql` — 마이그레이션 (TIMESTAMPTZ)
2. `TriggerSource`, `SyncRunStatus` enum
3. `PriceSyncRun` entity
4. `PriceSyncRunRepository` (Spring Data JPA + custom impl, REQUIRES_NEW)
5. `SyncJobSchedule` config (Clock 주입)
6. `AsyncConfig` + `syncCatchUpExecutor` + `@EnableAsync`
7. `ScrydexSyncService`
8. `KoEstimatedSyncService`
9. `SyncCatchUp` (EventListener + watchdog)
10. `PriceSyncScheduler.syncGlobalPrices()` + `refreshKoEstimates()` 본체 수정
11. `compileJava` 통과 검증

## 브랜치

`feat/price-sync-catchup` (dev 기반 worktree: `../pokemon-card-app-sync`)

## Kill switch (운영 보호 장치)

기본값 `false` — 로컬/베타 가동 시 의도치 않은 catch-up 실행 차단.

```properties
# application.properties
price.sync.catchup.enabled=${PRICE_SYNC_CATCHUP_ENABLED:false}
```

`false` 동안의 동작:
- `ScrydexSyncService.runIfNeeded()` / `KoEstimatedSyncService.runIfNeeded()` 진입부에서 `log.info` 후 즉시 `SKIPPED` return
- CRON / STARTUP / WATCHDOG **모든 trigger 차단** (CRON 본체도 함께 차단되므로 운영 전환 시 신중히)
- watchdog의 `reapStaleRunning`은 별개로 동작 (메타데이터 정리는 안전)

운영 전환 절차:
1. DB 마이그레이션 적용 (아래 Bootstrap 섹션 참조)
2. `PRICE_SYNC_CATCHUP_ENABLED=true` 환경변수 또는 `application-prod.properties`에서 명시
3. bootRun 재가동
4. 첫 watchdog (10분 이내) 또는 startup catch-up 시 정상 동작 확인

## Bootstrap (전환 절차)

`price_sync_runs` 첫 도입 시 기존 `price_snapshots`에 SCRYDEX row가 있어도 `price_sync_runs.SUCCESS` 기록은 없음.
이 상태에서 catch-up enable 시 **23:45 KO_ESTIMATED가 "SCRYDEX_DAILY SUCCESS 없음"으로 skip** 가능.

### 권장 순서

```bash
# 1. 마이그레이션
psql -d pokemon_card_db -U nightfury -f back/sql/price_sync_runs_migration.sql

# 2. Bootstrap (기존 SCRYDEX 적재일 기준 SUCCESS 시드 — 최근 7일)
psql -d pokemon_card_db -U nightfury -f back/sql/price_sync_runs_bootstrap.sql

# 3. 검증
psql -d pokemon_card_db -U nightfury -c "
SELECT business_date, status, row_count_en, row_count_jp, trigger_source
  FROM price_sync_runs
 WHERE job_name = 'SCRYDEX_DAILY'
 ORDER BY business_date DESC;"

# 4. (선택) catchup enable
export PRICE_SYNC_CATCHUP_ENABLED=true
cd back && ./gradlew bootRun
```

### Bootstrap 미실행 시 영향

- 첫날 catch-up enable → SCRYDEX run record 없음 → KoEstimated catch-up이 "SCRYDEX SUCCESS 없음"으로 skip
- 다음날 21:00 정규 cron부터 정상화 (단, 첫날 KO_ESTIMATED 갱신 누락)

따라서 bootstrap SQL은 **선택이 아니라 권장**. 첫 도입 후 1회만 실행하면 됨 (ON CONFLICT DO NOTHING 가드).

