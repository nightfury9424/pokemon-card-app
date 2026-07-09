# SESSION HANDOFF — 2026-06-27

> 다음 세션 진입점. 먼저 이거 읽고 → 사용자한테 실기기 테스트 결과 받고 → **SNKRDUNK 데이터 분석** 시작.

## 0-Z. ★★최신 (2026-06-28) = 게시글 상세 레이아웃 정리 + 보존 + IPA
- 상세 읽기흐름 재정렬: **제목→본문(붙임)→작성자·시간·조회(본문 아래 작은 메타·아바타 제거)→좋아요/댓글→divider→댓글**. board_detail_screen.dart front-only. 프론트 233/0·analyze0·골든(small/large/long/empty) overflow0.
- ★**/tmp 워크트리 사고**: 날짜 경과로 `/tmp/pf_board_release` base 파일 651개 삭제됨(내 작업 무손실). git worktree라 커밋된 `integ/board-release-1.0.4`(4b75b3cf)에서 삭제분만 복원. ★**보존 완료**: Front **commit `152abdba`**(integ/board-release-1.0.4, 27파일, 워킹트리clean) / Backend **tar `~/Downloads/myactivity_backend_20260628.tgz`**(+/tmp). ★/tmp는 또 정리될 수 있음 — 작업은 커밋 보존됨.
- Backend = **신규 변경 0**(detail은 front-only). myactivity-20260627 여전히 LIVE(재확인 healthy).
- 글쓰기 FAB 아이콘 `+`→**연필**(edit_rounded, pill 유지) — 사용자 요청. front-only·commit `275ed94d`.
- **최신 IPA = `1.0.4 (202606280254)`**(상세레이아웃+내활동+MY구조+polish+스캐너원복·라벨+글쓰기연필), SHA 0f1c1fcb, Transporter. 보존 commit `152abdba`→`275ed94d`(integ/board-release-1.0.4). 다음=TestFlight 실기기→제출판단.

## 0-A. (2026-06-27 오후) = 내 활동 기능
- **MY 구조 재편 + 내 활동(내가 쓴 글/댓글 단 글)** 구현 완료. **Backend additive 운영 배포 LIVE**(이미지 `myactivity-20260627`=4a2f24b9, 롤백 `rollback-pre-myactivity-20260627`=2a6ffd60). **DB 마이그 0**.
- 신규 엔드포인트 `GET /api/board/me/posts`·`/me/commented-posts`(인증, 비로그인 403[기존 board GET과 동일]). 백엔드 254/0·class-diff board 5클래스만·스모크 통과(내글 200·댓글단글 200·회귀 200).
- 신규 IPA = **`1.0.4 (202606271539)`**(MY구조+내활동+게시판polish+스캐너원복+가격라벨), SHA 35860228, Transporter. 프론트 233/0.
- **270902 = 안정 RC 보존**(롤백 후보). App Store 제출 금지. 다음 = TestFlight 실기기(내 활동 포함) → 사용자 제출 판단.

## 0. 한눈에 (오전 = view/notify, 위 0-A가 최신)
- ★게시판 **조회수 + 알림** = 운영 Backend **배포 LIVE** + **실기기 검증 전부 PASS**(2026-06-27): 조회수 정확(DB 14/14)·인앱배너·**FCM 푸시 실도착**·**알림 탭→딥링크 이동**·dedup/읽음·self/차단 제외. **기능/UI 검증 종료.**
- ★Front polish: 게시판 UI(텍스트형 메타·`+글쓰기` pill·상세 라벨) **유지** / 스캐너 polish는 **사용자가 별로라 원복**(가격 라벨 `한국판 예상가`만 유지).
- 최신 IPA = **`1.0.4 (202606270902)`**(스캐너 원복판, SHA 72e6c320) Transporter. 이전 270844=스캐너 polish판(폐기).
- **남은 것 = App Store 심사 제출 여부 = 사용자 결정만**(난 준비완료·승인 전 제출 금지).
- 다음 세션 = **SNKRDUNK 데이터 분석**.

## 1. 이번 세션 완료물

### A. 게시판 조회수 + 알림 — 운영 LIVE (백+DB+프론트)
- **기능**: 조회수(`POST /api/board/posts/{id}/view` 멱등·`board_post_views` `(post_id,viewer_id)` PK·작성자/숨김/삭제/비로그인 제외) + 알림(좋아요/댓글/대댓글, `dedup_key`, self·차단(양방향) 제외, `@TransactionalEventListener(AFTER_COMMIT)` + `REQUIRES_NEW`, FCM 실패 흡수=알림row 보존) + 댓글 딥링크(`/board/:postId?comment=`, getOffsetToReveal 스크롤).
- **8개 품질 게이트 전부 CLOSED**: 백엔드 전체 **248/0/0**, 프론트 **228/0**, 마이그 forward/rollback dry-run, 실이벤트흐름·동시성·FCM격리 통합테스트, 재현성 patch.
- **운영 배포(2026-06-27 05:03 LIVE)**: 백업→마이그(트랜잭션)→clean staging→JAR class-diff(비관련 0)→임시컨테이너 통제스모크(실유저 325 푸시 **0**)→Backend 교체→라이브 재스모크 전부 PASS. 운영 데이터 무결(notif 59·posts 31).
  - 신규 이미지 `pokefolio-back:viewnotify-20260627`(sha256:2a6ffd60…). **롤백 태그 `rollback-pre-viewnotify-20260627`(=ae01fe2f).**
  - 마이그 LIVE: `board_post_views` + `notifications.dedup_key` + `uq_notifications_dedup`.
  - release dir = `/opt/pokefolio/releases/viewnotify-20260627`. 스키마 백업 = prod `/tmp/pf_schema_backup_20260627_0448.sql`.
- **상세 산출물/절차/롤백** = `docs/BOARD_VIEW_NOTIFY_DEPLOY_20260627.md` + tarball `~/Downloads/board_view_notify_deploy_20260627.tgz`(FILELIST.txt=overlay 14파일 권위목록).

### B. 게시판 UI polish (Front-only, IPA만)
- 목록: 좋아요·댓글·조회 **아이콘 제거 → 텍스트형** `좋아요 N · 댓글 N · 조회 N`(토스식, muted). `자유` 칩 글자만(공식만 아이콘). **`+ 글쓰기` compact pill**(큰 직사각형/원형연필 폐기).
- 상세: `♡ 좋아요 N   댓글 N`(하트 아이콘+라벨) + 조회는 작성자 메타 `닉 · 시간 · 조회 N`. 댓글 전송 종이비행기·입력창 슬림.
- 골든 프리뷰: `~/Downloads/board_preview_{LIST,DETAIL}.png`(AppleGothic 로드 렌더; □는 SF아이콘 글리프 미존재일 뿐 실기기 정상).

### C. 스캐너 가격 라벨 (Front-only)
- 스캔 결과 시트 가격 위 `한국판 예상가` 라벨(`PriceLabel.resolve`, card_detail과 동일 유틸). "290원"만 보여 시세 오해되던 것 해결.

### D. IPA 이력 (모두 ~/Downloads)
- `1.0.4 (202606270740)` = **최신**(UI polish + 스캐너 라벨), SHA `43833762…`.
- `…270643`(SF아이콘 시도) · `…270542`(UI polish 1차) · `…270506`(view/notify front).
- 안정 RC `202606262337` 보존(배포 전 기준선).

## 2. 워크트리/소스 위치 (★중요 — drift 주의)
- **백엔드 = `/tmp/pf_viewnotif`** (운영 ae01fe2f staging pull, 컴파일+248/0). board_release 백엔드는 AdminAddCardRequest 누락으로 미컴파일 → 백엔드는 **viewnotif에서만**.
- **프론트 = `/tmp/pf_board_release/front`** (브랜치 `integ/board-release-1.0.4`, 미커밋). IPA 여기서 빌드. 미커밋 변경 = view/notify 4 + UI polish(board_screen·board_detail_screen) + scanner_screen + 테스트 + 골든 프리뷰파일.

## 3. 검증 완료 (2026-06-27) — 더 할 것 없음
- ✅ 조회수(DB 14/14 실제글 일치·dummy 시드글 제외) · ✅ 알림 생성(DB 56: 댓글46/답글4/좋아요6)·dedup 0중복·읽음 · ✅ **인앱 배너**(댓글·좋아요) · ✅ **FCM 푸시 실기기 도착** · ✅ **알림 탭→게시글/댓글 딥링크 이동** · ✅ self/차단 제외(통합10/0+스모크) · ✅ 게시판 UI · ✅ 스캐너 원복.
- ✅ **금칙어 검열 운영 LIVE 검증**: 게시글 title/content + 댓글/대댓글 content save 전 차단(403)·prod profile=prod fail-closed·번들 txt 4,164개. enforce 소스=JAR 번들 txt(DB 테이블 아님). [[project_board_moderation_4gate_pending_20260623]]

## 3-1. 현재 = **개발 동결**. 제출 직전 1분 스모크만 (사용자 결정)
- ★**추가 개발/빌드/제출 전부 정지.** 코드 손대지 말 것.
- **제출 직전 `1.0.4 (202606270902)` 빌드로 1분 스모크**(기능 깊은 재테스트 X, 제출할 그 빌드 화면만):
  - ☐ 게시판 목록/상세 진입 ☐ 댓글 1개 작성 ☐ 알림 탭 이동 1회
  - ☐ 스캐너 화면 **원복** 확인 ☐ `한국판 예상가` 라벨 보임 ☐ 거래/채팅/홈 기본 진입 이상 없음
  - (+ Transporter Deliver 눌러 TestFlight 실제 도착 확인)
- 이상 없으면 → **App Store 제출 여부 = 사용자 결정** → 제출 후 **코드 동결** → 다음 세션 SNKRDUNK.
- ★**출시후 TODO(블로커 아님)**: 금칙어 enforce 소스=번들 txt 4,164개로 기록. 관리자 금칙어 화면(있다면 DB)↔실 enforce(번들txt) 동일 소스인지 출시 후 확인.

## 4. 다음 세션 메인 ② = SNKRDUNK(스닉덩크) 데이터 분석
- **컨텍스트**(마스터 플로우 5단계, `docs/MASTER_FLOW.md`): 심사 대기 공백에 **SNKRDUNK 운영화**. 기존 수집기 인수인계, **확정 매핑만 `SNKRDUNK_SOLD_JP` 승격, raw 직접 적재 금지**. JP 트랙(KO와 분리·v8 최종에서만 합침).
- **착수 전 읽을 것**: `docs/MASTER_FLOW.md`, 기존 SNKRDUNK 수집기 코드/스크립트, [[project_v8_ko_ground_truth_naver_20260620]](JP는 SNKRDUNK로 분리), [[feedback_backup_first_operations]].
- 사용자가 분석 방향/데이터 제시 예정. **raw 직접 적재·시세 로직 변경은 승인 전 금지.**

## 5. 절대 금지
App Store 제출 / 운영 시세·조회수·알림 로직 임의 변경 / PENDING 신고 임의 처리·삭제 / SNKRDUNK raw 직접 적재 / prod 직접 수정(백업+diff+롤백+승인 없이).

## 6. 핵심 명령
- IPA: `cd /tmp/pf_board_release/front && flutter build ipa --dart-define=BASE_URL=https://d33b273n14t3ne.cloudfront.net --dart-define=CARD_CDN_BASE=https://d3shjhylvfe40j.cloudfront.net/cards/v1 --build-number=$(date +%Y%m%d%H%M)` → Transporter.
- prod SSH: `ssh -i /Users/fury/pem/LightsailDefaultKey-ap-northeast-2.pem ubuntu@52.78.3.120`
- 백엔드 롤백: `sudo docker tag pokefolio-back:rollback-pre-viewnotify-20260627 pokefolio-back:latest && cd /opt/pokefolio/app && sudo docker compose -f docker-compose.prod.yml up -d --no-build --no-deps --force-recreate back`
- DB 마이그 롤백: `viewnotify-20260627/back/sql/board_view_notify_rollback.sql`(view_count·알림row 보존).
