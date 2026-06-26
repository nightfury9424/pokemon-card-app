# 게시판 모더레이션 + 검색/공지 배포 runbook (2026-06-26)

> ★현재 운영 **미변경**(running `7ee334d7`, live dist `index-N8GFmNfy.js`, DB 미마이그, nightfury block row 1건 유지).
> 아래 Deploy 섹션은 **네 신호 후** 실행. App Store 제출은 별도 승인.

## 준비 완료 (실행 안 함)
- **백업** `prod:~/predeploy_20260626/`: back_inspect.json·back_env.txt·docker-compose.prod.yml·admin_dist_live.tar.gz(SHA c0719285)·reports_schema.sql(105줄)·reports_data.sql(2 row)·reports_indexes.sql·blocks_nightfury.csv(1 row)
- **롤백 태그** `pokefolio-back:rollback-pre-moderation-20260626` = `7ee334d7`
- **신규 Backend 이미지** `pokefolio-back:board-moderation-20260626` = `946045c4` — clean staging `/opt/pokefolio/releases/moderation-20260626`(prod base + 승인 10 Java + 2 SQL, 허용 경로 외 diff 0, DEPLOY_MANIFEST.sha256). 검증: 컴파일 RC=0 · 부팅 14s · 검색 스모크 어비스아이 39·다크라이 21 (HTTP 200, 실데이터)
- **신규 Admin dist** 로컬 `/tmp/admin_dist_new.tar.gz`(JS `index-9zQVtCbW.js` 신규·CSS `index-DwEH7bzJ.css` live와 동일) — Notices(앱미리보기·운영팀댓글) 신규 + Reports(첨부이미지) preserved

## Deploy (revised order — 이미지/dist 빌드·검증은 이미 완료)
```bash
# 1) 백업 재확인
ls -la ~/predeploy_20260626/
# 2) 점검 모드 ON (S3 app-config/maintenance.json=true) — 짧은 전환(구 service가 신규 index 경쟁 500 회피)
# 3) DB migration (트랜잭션 BEGIN..COMMIT 내장)
docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db \
  < /opt/pokefolio/releases/moderation-20260626/back/sql/reports_dedup_migration.sql
docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c \
  "SELECT indexname FROM pg_indexes WHERE tablename='reports' AND indexname LIKE 'uq_%'"  # 2개 확인
# 4) 신규 Backend 이미지 기동 — ★full SHA 명시(latest 의존 최소화)
docker tag sha256:946045c416dea2620b44ec3954ed3e15794e284f679d5c8899341bf5e1656ba0 pokefolio-back:latest
cd /opt/pokefolio/app && docker compose -f docker-compose.prod.yml up -d --force-recreate --no-deps pokefolio-back
docker inspect --format='{{.Image}}' pokefolio-back   # ★946045c4... 인지 반드시 확인
docker logs --tail 30 pokefolio-back | grep "Started BackApplication"   # health
# 5) Backend API 스모크: 공식글 신고→report 1·block 0 / 일반글 신고→자동차단 / 검색 어비스아이 39 / 신고처리 200
# 6) Admin dist 교체 (기존 dist 백업 후 신규 dist 전체 교체)
cd /opt/pokefolio/app/admin && cp -r dist dist.bak_pre_moderation_$(date +%Y%m%d_%H%M)
#    (로컬 /tmp/admin_dist_final.tar.gz[SHA 1c3d7941] scp → prod → rm -rf dist/* && tar xzf … -C dist)
# 7) Admin 스모크: 공지 미리보기·운영팀 댓글 작성·신고 첨부이미지 표시
# 8) ★nightfury 잘못된 차단 row 정확히 1건 삭제 (#11) — 점검 OFF 전에
docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c \
  "DELETE FROM blocks WHERE block_id='ae9500e5b6e340c69b864cd334cff887'"
# 9) 삭제·재발 확인: nightfury blocked row 0 (공식글 재신고해도 자동차단 안 됨)
docker exec pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c \
  "SELECT count(*) FROM blocks WHERE blocked_id='USR_F4B33078DB2B4672BEB0'"   # 0 이어야
# 10) 점검 모드 OFF
# 11) 사용자 관점 전체 스모크(이미지·문의·Card·Price·Auth 정상) → 통과 후에만 IPA
```

## Rollback
```bash
# Backend
docker tag pokefolio-back:rollback-pre-moderation-20260626 pokefolio-back:latest
cd /opt/pokefolio/app && docker compose -f docker-compose.prod.yml up -d --force-recreate --no-deps pokefolio-back
# DB
docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db \
  < /opt/pokefolio/releases/moderation-20260626/back/sql/reports_dedup_rollback.sql
# Admin
cd /opt/pokefolio/app/admin && rm -rf dist && mv dist.bak_pre_moderation_* dist   # 또는 ~/predeploy_20260626/admin_dist_live.tar.gz 복원
# nightfury (필요 시 복원)
docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db -c \
  "\copy blocks FROM '~/predeploy_20260626/blocks_nightfury.csv' WITH CSV HEADER"
```

## 배포 후 실검 체크리스트
공식글 신고→report·block0 / 일반글 신고→자동차단 / 공식글 일반유저 댓글 차단가능 / 운영팀 댓글 신고가능·차단불가 / Admin 공지 댓글·대댓글 작성·앱 운영팀 배지·댓글수 일치 / Admin 신고 처리 성공(#4) / 어비스아이 검색 / 카운터 0포함 / 검색 복귀 상태유지·키보드닫힘 / 홈배너 / 이미지·문의·Card·Price·Auth 정상 → 통과 후 새 IPA.

## 배포 전 최종 검증 (4/4 통과, 2026-06-26)
1. **최종 staging 소스 전체 테스트** — staging(prod base+내10) + 내 테스트 9파일 로컬 조립, `cleanTest test` = **252 / 0 fail / 0 error / 0 skip**(29클래스, #14 6/0·#15 8/0).
2. **base==prod 증명(JAR)** — `7ee334d7` vs staging `946045c4` BOOT-INF/classes 차이 = **내 10 클래스만**(+BoardService$ImageSummary inner), 그 외 0 / BOOT-INF/lib **0 diff(236 jar)**. → boardimg-pathscoped-20260625 = `7ee334d7`의 정확한 소스 + staging = base+내10 확정.
3. **admin 최종 dist vs live — 결정적 증명(한글 문자열 집합)**: 내 최종 dist(`9zQVtCbW`) vs live(`N8GFmNfy`) 한글 문자열 비교 = **live 에만 0개(제거 없음 — 상단고정 메시지·Reports 첨부이미지 전부 보존)** + **final 에만 24개 = 전부 내 Notices 추가**(앱 미리보기·운영팀 댓글/답글 입력 등). admin/ git 변경 = Notices+Reports 2파일뿐(Reports=live, package/lock/config 무변경). → **배포 delta = 내 Notices 추가뿐, 제거 0** 확정. (live JS≠baseline 해시차 원인 = live Notices의 uncommitted-but-live 상단고정 문자열, 내 working엔 이미 포함)
4. **백업·마이그·롤백 사이클(임시 DB, ON_ERROR_STOP=1)** — schema/data 복원 OK → migration(uq 2개) OK → rollback(원본 정확복원) OK. nightfury 정확히 1건.

### 기록 SHA / 식별자
- 신규 Backend 이미지: **`sha256:946045c416dea2620b44ec3954ed3e15794e284f679d5c8899341bf5e1656ba0`** (tag `board-moderation-20260626`)
- 롤백 이미지: `pokefolio-back:rollback-pre-moderation-20260626` = `7ee334d7`
- 최종 Admin dist tar SHA-256: **`1c3d79419ba4754c5f348483492d377c9334ba2f2203c2068203b901fe76122d`** (JS `index-9zQVtCbW.js` 신규 / CSS `index-DwEH7bzJ.css` = live)
- live Admin dist JS(보존): `index-N8GFmNfy.js`
- nightfury 삭제 대상: block_id `ae9500e5b6e340c69b864cd334cff887`
- healthcheck(postgres): `pg_isready -U nightfury -d pokemon_card_db` / Backend: "Started BackApplication" 로그 + 검색 API 200

## 배포 실행 기록 (CP1, 2026-06-26 ~06:27)
- ★compose **서비스명 = `back`** (컨테이너명 `pokefolio-back` 아님). 컨테이너명으로 `compose up <name>` 하면 **무동작**(서비스 못 찾음). 배포 명령은 **exit code·stderr 보존**(/dev/null 금지) 필수 — 1차 시도에서 서비스명 오류+stderr 가림으로 미교체를 놓쳤음.
- migration COMMIT은 즉시(2-row 테이블), 정상 교체 시 Backend Started ~13s. 단 1차 실패로 **구 Backend+신규 index 노출 ~2분** 발생 — 그 구간 5xx **0**(구 앱이 app-level dedup으로 먼저 차단). 2차에서 `back` 서비스명으로 정상 교체(실행 .Image=946045c4 확인).
- CP1.5 라이브 스모크(SMOKETEST 통제데이터): 공식글 신고 block0 / dedup per-target / 자유글 autoblock / OTHER 400·성공 / 운영팀 댓글 200·is_admin=t·자유글 403 — 전부 PASS, 잔존 0.

## 현재 진행 상태 (2026-06-26)
**완료(운영 반영됨)**: DB migration COMMIT · Backend `946045c4` 기동·healthy · CP1.5 라이브 스모크 · **Admin dist 신규(9zQVtCbW) 교체** · CP2 서버 스모크 · **#4 신고처리 라이브** · **#11 nightfury 오차단 삭제(blocks=0·재발0)** · **#13 운영팀 댓글 라이브(is_admin=true 2건)** · SMOKETEST 전량 cleanup(잔존0).
**새 IPA(빌드 완료, 업로드 대기)**: `front.ipa` 46.6MB · 버전 1.0.4 · build **202606260712** · arm64-only · SHA-256 `bcb103f589e60ce407b2ec9bc9aa1b4fbfbdb833f2b26bf0db636402ce54f2db`.
**#5 보완 배포 (2026-06-26 ~09:14, Backend-only)**: `/cards/market`(거래/시세 검색=trade_search 본결과) 세트명 매칭 누락 → 추가. 신규 이미지 `board-market-20260626`(manifest `7ec9712d`) = 946045c4 + **CardRepository.class 1개만**(JAR BOOT-INF/classes diff 1·lib 0 diff/236). getMarketCards 8 데이터쿼리 + countByRarityAndName, **promo(/market/promos) 범위밖 원복**(세트명 매칭 총 11=/search 2·/market 8·count 1). 임시컨테이너+라이브 검증: market 어비스아이 **39**·search 39·다크라이 19·browse **3414 불변**·promo 42·5xx 0. 롤백태그 `pokefolio-back:rollback-pre-market-20260626`=946045c4. **DB/Admin/Front 미접촉, IPA(202606260712) 재빌드 안 함**(Front 무변경).
**미실행(금지)**: TestFlight 업로드(사용자 Transporter) · App Store 제출.
