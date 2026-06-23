# 게시판 쓰기 슬라이스 설계안 (Slice 2) — 승인 대기

> 브랜치 `feat/board-read-backend`(off `dev`@75485a41) 연속. **설계안 — 승인 전 구현·운영DB·배포·프론트 금지.**
> 권한 모델 = `BOARD_READ_BACKEND_DESIGN.md` §10 (사용자/관리자 API 분리·서버측 authz·fail-closed). 본 문서는 그 위 쓰기 계약.
> 이 슬라이스 범위: 사용자 작성/본인수정·삭제/댓글·1단답글/금칙어 + 관리자 공식글 CRUD/일반글·댓글 숨김·복구/감사로그.
> **이번 슬라이스 제외(다음으로 분리)**: 좋아요·조회수·신고확장·Q&A 채택.

## 1. 조사 결과 (설계 근거)
- 관리자 식별: `AdminAllowlistFilter` — allowlist=`ADMIN_USER_IDS`(env, 콤마구분 user_id), 토글=`ADMIN_AUTH_ENABLED`(env, default false). **빈 allowlist → 403(fail-closed)**. principal=실 JWT userId. `isAllowed(userId)` **공개 메서드**(서비스 재검증 재사용).
- 운영 전용 계정: users 테이블에 system/admin/ops/'운영팀' row **없음** → **합성 계정 하드코딩 금지**. → 공식글 `author_id` = **인증된 관리자 실 userId**(allowlist 구성원=실 users 행). 표시명만 "운영팀"(`BoardTaxonomy.isAdminType`).
- 감사로그: `AdminActionService.record(adminUserId, actionType, targetType, targetId, memo, prevState, newState)` — **실 actor(adminUserId) 기록**.

## 2. 관리자 공식글 author 처리 (★확정)
- 화면 표시명 = 항상 `운영팀`.
- 요청 `authorId` **무시**.
- DB `author_id` = **인증된 관리자 실 userId**(allowlist 구성원). 합성 ops 계정 미생성(없으므로). 향후 단일 운영계정 원하면 **검증된 seed 마이그**로 생성 후 사용(하드코딩 금지) — 이번 슬라이스는 실 관리자 userId.
- author 계정 row 미존재 시 **작성 실패**(방어).
- `admin_actions` 에는 실제 수행 관리자 userId 기록(다수 관리자 구분).

## 3. API 계약
### 사용자 (`/api/board/**`, 인증 필요)
| 메서드·경로 | 동작 | 주요 상태코드 |
|---|---|---|
| `POST /api/board/posts` | 일반글 작성(user 타입만) | 201/200·**401**(미인증)·**403**(official 타입)·**400**(잘못된 type/공백/금칙어) |
| `PATCH /api/board/posts/{id}` | 본인 user글 제목·본문 수정 | 200·401·**403**(비소유·official)·**404**(미존재/삭제/숨김)·400 |
| `DELETE /api/board/posts/{id}` | 본인글 소프트삭제 | 200·401·403·404 |
| `POST /api/board/posts/{postId}/comments` | 댓글/1단 답글 작성 | 201/200·401·**404**(게시글 없음)·**400**(parent 부적합/공백/금칙어) |
| `DELETE /api/board/comments/{commentId}` | 본인 댓글 소프트삭제 | 200·401·403·404 |

### 관리자 (`/api/admin/board/**`, AdminAllowlistFilter + 서비스 재검증)
| 메서드·경로 | 동작 | 비고 |
|---|---|---|
| `POST /api/admin/board/posts` | **공식글(notice/event/patch)만** 작성 | user 타입 요청=403. author=서버결정(관리자 userId), isPinned 허용, 감사로그 |
| `PATCH /api/admin/board/posts/{id}` | **공식글만** 제목·본문·isPinned 수정 | ★대상 post.type∈official 아니면 **403**(사용자 글 내용 임의수정 금지). 감사로그 |
| `DELETE /api/admin/board/posts/{id}` | 소프트삭제(`deleted_at`=now) — 공식·사용자 글 모두(모더레이션) | 감사로그 |
| `PATCH /api/admin/board/posts/{id}/moderation` | action: `HIDE`/`UNHIDE`(status)·`RESTORE`(`deleted_at`=NULL **만**) — 공식·사용자 모두 | ★두 축 독립, 감사로그 |
| `DELETE /api/admin/board/comments/{commentId}` | 댓글 소프트삭제(`deleted_at`=now) | 감사로그 |
| `PATCH /api/admin/board/comments/{commentId}/restore` | 댓글 복구(`deleted_at`=NULL) | ★댓글은 status 컬럼 없음→delete/restore만, 감사로그 |

응답 래퍼 = `ReturnData`. 400/404/403 = `ResponseStatusException`(GlobalExceptionHandler 가 실제 status 보존).

## 4. 요청 DTO (서버 신뢰 필드만 수용)
- `CreatePostRequest { type, title, content }` — section/authorId/isAdmin/isPinned/status **수용 안 함**.
- `UpdatePostRequest { title, content }` — type 변경 불가(official 승격 차단).
- `CreateCommentRequest { content, parentCommentId? }`.
- `AdminCreatePostRequest { type, title, content, isPinned? }` — authorId 무시.
- `AdminUpdatePostRequest { title?, content?, isPinned? }`.
- `PostModerationRequest { action }` — `HIDE`|`UNHIDE`|`RESTORE`. HIDE/UNHIDE=`status`만, RESTORE=`deleted_at` NULL **만(status 불변)**. ★삭제 복구가 숨김글을 자동 공개하지 않음 — 공개는 별도 UNHIDE. (댓글 삭제/복구는 경로로, body 없음 — 댓글엔 status 컬럼 없음.)
- 검증: title 1..200, content 1..10000(초과 거부 또는 컷 — 거부 채택), comment content 1..2000. trim 후 공백 거부.

## 5. 권한 판정표 (서버)
| 행위자 | 대상 | 허용 | 거부 |
|---|---|---|---|
| 미인증 | 쓰기 전체 | — | 401 |
| 사용자 | 일반 타입 작성 | ✅ | official 타입=403 / 잘못된 type=400 |
| 사용자 | 글 수정·삭제 | 본인글 | 타인글=404(존재 비노출)·official=403 |
| 사용자 | 댓글 작성 | ✅(존재 게시글) | parent 타 게시글/답글의 답글=400 |
| 사용자 | 댓글 삭제 | 본인 댓글 | 타인=404 |
| 관리자 | 공식글(notice/event/patch) 작성·수정·삭제 | ✅(필터+서비스 재검증) | user 타입 작성/수정=403 |
| 관리자 | 사용자글·댓글 숨김/해제/삭제/복구(모더레이션) | ✅ | 사용자글 **내용 수정 불가**·비관리자 토큰=403 |
| 관리자 | Q&A 채택 | ❌(이번 슬라이스 외·OP 전용) | — |

서버 authz 불변식: 클라 `isAdmin/isOfficial/section/authorId` 불신 · section=type 서버도출 · official 쓰기=관리자 경로만 · 사용자글 내용수정=관리자 불가(모더레이션만) · 본인판별=`author_id==userId` 아니면 404.

### 댓글·답글 검증 규칙
- 대상 게시글이 **ACTIVE & deleted_at NULL** 이어야 작성 가능 → 삭제·숨김·미존재 게시글 = **404**(존재 비노출).
- `parentCommentId` 있으면(답글): ①동일 `post_id` 댓글이어야(아니면 400) ②부모는 **최상위**(parent_comment_id NULL)여야(답글의 답글 금지=400) ③부모가 **삭제(deleted_at)** 면 금지(400).
- 즉 **같은 게시글의 삭제되지 않은 최상위 댓글에만 답글** 허용. 위반=400, 게시글 비노출=404.

## 6. 상태 전이
- post.status(가역 숨김 축): 신규=`ACTIVE`. 관리자 HIDE→`HIDDEN`, UNHIDE→`ACTIVE`. 읽기 노출=status=ACTIVE **그리고** deleted_at NULL.
- post.deleted_at(삭제 축): 삭제(본인/관리자)=now. **관리자 RESTORE = deleted_at NULL 만 클리어, status 불변**(★삭제 복구가 숨김글을 자동 공개하지 않음 — 공개는 UNHIDE 별도). 두 축 완전 독립.
- post.updated_at: 수정 시 갱신.
- comment: **status 컬럼 없음 → deleted_at 단일 축.** 삭제=now, 관리자 복구=deleted_at NULL. 삭제 댓글+답글존재=읽기 placeholder(규칙 유지).
- **이번 슬라이스 미변경**: view_count, like_count, is_answered, is_accepted(=0 유지).

## 7. 마이그레이션 변경사항 + 롤백
- **신규 테이블/컬럼 없음** — 쓰기는 `board_read_migration.sql` 스키마(status·deleted_at·updated_at·is_pinned 등) 그대로 사용. ★스키마 마이그 불필요.
- ★**무결성 CHECK 확정(이번 슬라이스 포함)** `board_write_constraints_migration.sql` — 쓰기 시작 → DB 레벨 방어(수동 SQL·버그로 잘못된 행 차단, blocks 선례):
  - `chk_board_posts_status`: status ∈ ('ACTIVE','HIDDEN').
  - `chk_board_posts_type_section`: **type↔section 조합 일치**(type·section 허용값 + 매핑을 한 번에 강제):
    `(section='official' AND type IN ('notice','event','patch')) OR (section='community' AND type IN ('free','tradeReview','scamAlert')) OR (section='qna' AND type='qna')`.
  - 롤백 `board_write_constraints_rollback.sql`: 두 CONSTRAINT DROP.
  - 로컬 격리 DB 적용→catalog검증→롤백→재적용 검증 후 채택. 운영 적용은 별도 승인+백업 선행.
- 운영 적용은 별도 승인 + 백업/복원 경로 검증 선행(읽기 슬라이스와 동일 게이트).

## 8. 재사용/신규 컴포넌트
- **ContentFilter(신규 서비스)**: `NicknameValidator` 의 **banned-word 목록만** 재사용(reserved/impersonation 등 닉네임 전용 정책 제외) → `containsBanned(title/content)`. 사용자 작성/수정·댓글 작성에서 호출, 위반 시 400.
- **관리자 authz 컴포넌트 분리(SSOT)**: 웹 필터를 서비스가 직접 의존하지 않음. 신규 `AdminAuthorizationService`(관리자 userId 파싱·allowlist 판정의 단일 진실원)를 만들어 `AdminAllowlistFilter` 와 `BoardAdminService` **양쪽이 사용**. Board admin 서비스는 `adminAuthorizationService.isAdmin(currentUserId)` 로 재검증. 기존 필터는 이 컴포넌트에 위임(동작 동일, 회귀 0 확인).
- **fail-closed 강화**: 현재 `StartupValidator` 가드는 프로필명(`prod`/`staging`) 매칭 의존 → **비-local 프로필 전반에서 `ADMIN_AUTH_ENABLED` 미설정 시 무조건 차단/시작 실패**하도록 강화(이름 매칭 의존 제거). admin 경로가 기본 개방되는 경로 차단.
- **감사로그**: `AdminActionService.record(adminUserId, ...)` — 공식글 작성/수정/삭제/숨김·복구·댓글 모더레이션마다 기록.

## 9. 구현 시 테스트 계획 (승인 후)
- 권한 매트릭스: 미인증 401 / 사용자 official 작성 403 / 잘못된 type 400 / 타인글 수정·삭제 404 / 관리자경로 비관리자 토큰 403.
- 소유권: 본인글·본인댓글만 수정·삭제.
- section 서버도출(클라 section 무시) · authorId 무시(공식글 author=관리자 userId, 표시 "운영팀").
- 금칙어 작성·댓글 400.
- parent 검증: 다른 게시글/답글의 답글 400.
- 감사로그 기록(관리자 행위마다 1행, 실 actor).
- 관리자 author 계정 미존재 시 작성 실패.
- (CHECK 채택 시) 위반 INSERT 거부.
- 전체 회귀(read 슬라이스 영향 없음 확인).

## 10. 명시적 제외 (이번 슬라이스 밖)
좋아요·조회수증가·신고(BOARD_POST targetType 확장)·차단 author 쓰기영향·Q&A 채택(OP 전용)·프론트 작성 UI·prod 적용/배포/dev 통합.

## 12. 공용 코드 최소화 결정 + 배포 게이트 검증 (2026-06-23)
- ★**공용 admin 인증 코드 무변경 결정**: 더 작은 변경으로 동일 안전성 달성 가능 → 기존
  `AdminAllowlistFilter`·`DeletedUserGuardFilter`·`AdminStage0Service`를 **원복(read 브랜치와 바이트 동일)**.
  → 기존 admin 기능(로그인·whoami·비관리자 403·정지 차단·관리자 면제·신고/문의/차단/채팅/거래 관리·감사로그)
  **회귀 정의상 0**. board 서비스는 신규 **독립** `AdminAuthorizationService`(필터와 **동일 config 키**
  `app.admin.user-ids`/`auth-enabled`, 발산 불가)로 admin 재검증 → 웹 필터 직접 의존 없음 + 공용 코드 무변경.
- ★**전체 검증 결과(배포 동등 격리 DB)**:
  - 격리 `pokefolio_ci`(엔티티 생성 스키마=validate 기준) + 더미 deploy config → **전체 `./gradlew test` green: 50/0**.
    `BackApplicationTests`(전체 앱 컨텍스트 부팅)·`BoardContextBootTest`·board 48 전부 통과.
  - 공용 admin 3파일 diff = 0(원복 확인). CHECK 마이그 격리 PG apply→거부→롤백→재적용 검증 완료.
- 배포 전 잔여 게이트(승인 영역): ①최신 dev rebase 후 충돌/누락 ②실제 배포 스키마(마이그 기반)와
  `ddl-auto=validate` 정합성 최종 확인 ③운영 DB 백업+복원 경로 검증 ④마이그 선적용 후 배포 ⑤이상 시 코드+DB 롤백.
  (로컬 dev DB `pokemon_card_db`는 board 무관 기존 drift[`buy_orders.active_chat_room_id`]로 그대로는 full-boot 불가 →
  배포 환경/CI 또는 dev DB 정렬에서 최종 확인.)

## 11. 중복 등록 방지 (idempotency) — ★후속 필수(이번 슬라이스 제외, 명시 보류)
- 문제: 버튼 더블탭·네트워크 재시도 → 동일 글/댓글 중복 생성.
- 설계: POST(글·댓글)에 `clientRequestId`(or HTTP `Idempotency-Key`) 수용 → `(author_id, client_request_id)` 부분 UNIQUE 로 중복 차단(동일 키 재요청은 기존 결과 반환).
- 스키마 영향: board_posts/board_comments 에 `client_request_id` 컬럼 + 부분 unique 인덱스(별도 마이그) → 이번 슬라이스 스키마 최소화 위해 **미포함**.
- ★**다음 슬라이스 필수 작업으로 명시.** 그 전까지 완화 = 프론트 더블탭 가드 + 서버 단시간 동일내용 best-effort 거부(권장).
