# 게시판 조회수 + 알림 — 배포 재현성 MANIFEST (2026-06-27)

운영 DB 마이그·배포 **승인 대기**. 안정 RC `1.0.4 (202606262337)` + 운영 Backend `ae01fe2f` 보존. App Store 제출 금지.

## 1. 운영 base 기준
- 빌드 소스 = **moderation-wild-20260626** (= 운영 실행 이미지 `ae01fe2f` 를 빌드한 staging). 로컬 pull 사본 = `/tmp/wild_orig` (tarball `~/Downloads`·`/tmp/wildsrc.tgz`).
- 개발 트리 = `/tmp/pf_viewnotif` (= base 위에 본 변경만 overlay). board_release/prod_baseline 워크트리는 drift 로 사용 안 함(이유: board_release=프론트 브랜치라 AdminAddCardRequest 누락으로 백엔드 미컴파일, prod_baseline=구 board 35파일).

## 2. 변경 파일 — 운영 base 대비 main diff = **비관련 0** (정확히 **14파일 = 수정7+신규7**)

> ★정정(2026-06-27): 직전 보고서의 "신규 5 / 8파일 / 총 12"는 **카운트 오류**. `diff -rq` 가 `board/event/` 디렉터리를 한 줄("Only in board: event")로 접어 그 안의 3파일을 1로 셌음. **산출물(tarball·new_main/)에는 신규 7파일이 처음부터 전부 포함**(누락 아님, FILELIST.txt 로 검증). 정확한 신규 = 7.

**권위 overlay 목록 = `FILELIST.txt`** (숫자가 아니라 이 파일 목록을 overlay. 누락 시 배포 금지).
**수정 7** (base md5 → new md5, `base_md5.txt`/`new_md5.txt`):
| 파일 | base md5 | new md5 |
|---|---|---|
| board/BoardController.java | 13aeebd3 | e05530a8 |
| board/BoardLikeService.java | f4a7212d | 49771355 |
| board/BoardPostRepository.java | 170f8888 | 347ba3ed |
| board/BoardWriteService.java | a3142ffa | 0462ca4d |
| notification/Notification.java | b958b084 | 9a2b03f6 |
| notification/NotificationRepository.java | 6ca850ea | 3521a55b |
| notification/NotificationService.java | 2a5e655e | d61aad73 |

**신규 7** (md5): board/BoardPostView(8a6ee75b)·BoardPostViewRepository(f57c2b3d)·BoardViewService(6b12b748) · board/dto/BoardViewResponse(07710bc1) · board/event/BoardPostLikedEvent(cbf15a21)·BoardCommentCreatedEvent(517231e0)·BoardNotificationEventListener(a57fb9b9).

**SQL 신규**: `board_view_notify_migration.sql`(운영 forward) · `board_view_notify_rollback.sql`(운영 rollback) · `board_post_views_migration.sql`(테스트 스키마 전용·운영 미실행).

산출물: `modified_7files.patch`(269줄) + `new_main/` + `sql/` → tarball `board_view_notify_deploy_20260627.tgz`(`~/Downloads` + `/tmp`).

## 3. 테스트 (전부 green)
- **백엔드 전체 248 / 0 failure / 0 error** (cleanTest). 신규: `BoardViewCountIntegrationTest` 6/0, `BoardNotifyEventFlowIntegrationTest`(실흐름·동시성·FCM실패) 10/0. `BoardBlockTest` 13/0(현행 정책으로 교정), `NoticeFeedContractTest` 7/0.
- **프론트 전체 228 / 0** (analyze 0). 딥링크 위젯테스트 포함.
- 교체 테스트 6개(BoardController/BoardPermissions/BoardService/Report*Test) = moderation 정책본(실행 prod 코드에 통과), 핵심 검증(self-report 거부·blank viewer·admin 차단불가) 보존, @Test 손실 0.

## 4. 마이그레이션 검증 (스크래치 DB dry-run, prod 스키마 모사)
- board_post_views PK=(post_id,viewer_id) · FK post=ON DELETE CASCADE · **FK viewer=ON DELETE CASCADE(회원 탈퇴 비차단)**.
- notifications.dedup_key nullable=YES · `UNIQUE(dedup_key)`(PG NULLS DISTINCT=partial 동일) · `ON CONFLICT(dedup_key)` 정합 · 기존 null 다수 공존(forward 시 충돌 0).
- 동작: 조회 멱등(2회→1행·+1 한 번) · 알림 dedup(같은 key→1행) · 탈퇴 cascade(leftover 0).
- **rollback: board_post_views drop·dedup_key drop·view_count 미복원(6 보존)·알림 row 보존**. 재적용 멱등(board_post_views 재생성=빈→기존 시청자 재집계 가능).
- 알림 **물리 삭제 기능 없음**(코드 전수) → dedup 이력 영구.

## 5. 배포/롤백 절차 (승인 후)
1. 운영 schema 백업(board_posts·notifications DDL + dump).
2. clean staging = moderation-wild 재사용본에 위 12 main + 2 sql overlay (base_md5 로 적용 전 일치 확인).
3. forward 마이그(트랜잭션) → §4 사후 쿼리 재확인.
4. 임시 컨테이너 부팅 → 통제 계정 스모크(실유저 325 푸시 0, FcmService no-op or 통제토큰).
5. JAR class-diff(BOOT-INF/classes md5) = 12 클래스 + event만, 비관련 0.
6. Backend 교체 + 롤백 태그(현 ae01fe2f). 이상 시 rollback.sql + 이전 이미지.
7. 새 IPA(build-number > 202606262337).
8. **TestFlight 실기기 검증**(아래 §6 체크리스트).

## 6. 댓글 딥링크 — 상태 = **코드 구현 + 분기 테스트 완료 / 화면 밖 실제 자동 스크롤은 실기기 검증 필요** (완전 CLOSED 아님)
- 자동 검증 완료: 존재 댓글 분기·없는 댓글 안내 SnackBar·예외 없음(위젯테스트 2). 표준 API(`getOffsetToReveal`+`jumpTo`).
- **미검증(실기기 필수)**: off-screen 댓글로의 실제 offset 이동 위젯테스트는 이 Flutter 버전 하니스의 semantics-on-scroll assertion 으로 작성 불가 → 제거함. 새 IPA TestFlight 에서 반드시 확인:
  1. 화면 하단 댓글 알림 → 해당 댓글 위치 이동
  2. 대댓글 알림 → 해당 대댓글 위치 이동
  3. 삭제된 댓글 → 안내 후 게시글 상세 유지
  4. 숨김·삭제 게시글 → 안내 후 게시판 목록 복귀
  5. (조회수) 상세 진입 +1·재진입 미증가·작성자 본인 0·목록 복귀 갱신
  6. (알림) 좋아요/댓글/대댓글 수신·self/차단 미수신·탭→상세·기존 거래/채팅/시세 알림 회귀 0·unread badge

관련: [docs/MODERATION_DEPLOY_RUNBOOK_20260626.md], 메모리 project_board_view_notify_20260627, `FILELIST.txt`.
