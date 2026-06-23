# PROD 배포 기준선 정정 (2026-06-24, read-only 실측 기반)

> 기존 `docs/SESSION_HANDOFF.md`(board/integ 브랜치)의 배포 브랜치 표기가 **STALE**임을 정정.
> 실제 prod 서버 `/opt/pokefolio/app` read-only 조회로 확인. 비밀값 미포함.

## 실제 prod 백엔드 기준
- 배포 브랜치 = **`integ/prod-consolidated`** @ `060c7416c861646f9799025e55559f468a463b7d`
  (= `origin/integ/prod-consolidated`). prod는 이 브랜치를 pull → `docker compose build back` 으로 구동.
- ★기존 런북의 **`feat/trade-active-counterparty`** 배포브랜치 표기는 **오래된 정보**(현재 prod 아님).
- active profile = **`prod`** (`.env.prod` `SPRING_PROFILES_ACTIVE=prod`, 부팅 로그 "1 profile is active: prod").
- 실행 이미지: back `pokefolio-back:latest`(id b311179e, jar sha `bf46f74…`), scanner `pokefolio-scanner:latest`(id cf688001), postgres 14, grading. 4컨테이너.

## prod working-tree 미커밋 hotfix (git 밖, 영구 보존 완료)
prod working tree에 git 미반영 운영 hotfix가 떠 있었음(과거 수동 배포 잔존). 2026-06-24 캡처·보존:
- **백엔드 Java 9파일** → 브랜치 `hotfix/prod-capture-20260624` (커밋 `21681900`), tag `backup/prod-hotfix-backend-20260624`.
  - 로컬 재현빌드 jar SHA-256 = prod 실행 jar과 **byte 동일**(`bf46f74`) 검증.
  - 내용: GlobalPriceService(FROZEN계수·ABORT가드·KREAM jitter·차트=실KO·대표가 chart_price), PriceSnapshot(chart_price+getDisplayPrice), PriceSyncScheduler(price.sync.enabled FREEZE), CardRepository(보드 SQL), CardServiceImpl(NOT_SUPPORTED 트랜잭션 fix), AdminController(matchEnViaScanner), InternalAdminController(dry-run), Asset/Trade(getDisplayPrice).
- **scanner는 별도 계보**: 실행 컨테이너 `main.py`(sha `d0fe5213`, IDENTIFY_MAX_SIZE=1600 warpfix + match-en) ≠ app working-tree `scanner/main.py`(sha `08cfb6d1`, warpfix 없음). 실행 컨테이너본이 운영 진실 → 브랜치 `prod-scanner-runtime-20260624`(커밋 `0adcb569`), tag `backup/prod-scanner-runtime-20260624`.
- 외부 백업: `~/pokefolio_backups/prod_hotfix_capture_20260624/`(patch·diff·원본·app.jar·scanner 실행본·MANIFEST.sha256) + `~/pokefolio-secure-backups/` 에 bundle 이중 보존.

## chart_price 컬럼 (정식 migration 필요)
- prod DB `price_snapshots.chart_price` = `integer`, **nullable, default 없음, index 없음, comment 없음**.
- 행 1,334,834 중 220,026 채움(전부 `KO_ESTIMATED`, 다른 source 0).
- ★git 의 마이그·엔티티 양쪽에 없었음(수동 prod 반영). 정식 migration 필요:
  ```sql
  ALTER TABLE price_snapshots ADD COLUMN IF NOT EXISTS chart_price INTEGER;
  ```
  (백필은 nightly 배치가 KO_ESTIMATED 행에 채움. migration은 컬럼 추가만.)

## 배포 원칙 (회귀 방지)
- ★`integ/board-release-1.0.4`(dev 기반)를 prod에 **그대로 덮어쓰기 금지** — prod의 다수 백엔드 커밋 + 미커밋 hotfix 회귀.
- 게시판 배포 = **prod 베이스(060c741 + hotfix 커밋 + chart_price 마이그) 위에 게시판 변경 cherry-pick** → 회귀 테스트 → 신규 테이블 마이그(백업·single-transaction) → pull/build/up → health+smoke.
- prod 직접 수정·재시작은 백업+diff+롤백플랜+사용자 승인 후에만.
