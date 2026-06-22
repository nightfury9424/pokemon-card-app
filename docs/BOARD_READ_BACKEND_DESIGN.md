# 게시판 읽기 백엔드 설계안 (Slice 1A) — 승인 대기

> 범위: **읽기 토대만**. 글쓰기·댓글등록·좋아요·신고·차단실행·관리자작성은 **이 슬라이스 밖**.
> ★정정: **게시판 프론트는 아직 integration 브랜치(`integ/step1-merge-20260622`)에 있고 `dev`에는 미통합.**
>   이 백엔드 브랜치는 `dev@75485a41` 기준 **독립** 작업이며, 프론트 `BoardMock`→API 교체(1B)는
>   Step 1 통합 이후 별도 슬라이스다(이 브랜치는 백엔드만 — 프론트 파일 미수정).
> 브랜치: `feat/board-read-backend` (off `dev`@75485a41). prod DB 적용·배포·dev 직접커밋·프론트 수정 **금지**.
> 설계 승인됨(2026-06-23) → Slice 1A 구현 진행. prod/dev 통합은 별도 승인 대기.

---

## 1. 데이터 계약 (프론트가 이미 기대하는 형태)
- `BoardPost`{id, type, title, body, author, createdAt, viewCount, likeCount, isPinned, isAnswered, comments[], commentCount}
- `BoardComment`{id, author, body, createdAt, isAdmin, isAccepted, replies[](1단)}
- type 7종: `notice/event/patch`(관리자), `free/tradeReview/scamAlert/qna`(유저) — **프론트 enum 토큰 그대로 직렬화**(camelCase 유지).
- section 3종: `official`(notice/event/patch) · `community`(free/tradeReview/scamAlert) · `qna`. type→section 결정적.

## 2. 테이블 (제안 DDL — `back/sql/board_read_migration.sql` 로 적용 예정, 지금은 미적용)
관례 준수: VARCHAR id, snake_case, `IF NOT EXISTS`, DB FK 미선언(앱레벨 무결성=기존 inquiries/trade_post_views 패턴), 소프트삭제 `deleted_at`.

```sql
-- 게시판 읽기 토대. ddl-auto=validate → 코드 배포 전 선행 적용 필수(승인 후).
CREATE TABLE IF NOT EXISTS board_posts (
    post_id       VARCHAR(50)  PRIMARY KEY,
    type          VARCHAR(20)  NOT NULL,            -- notice/event/patch/free/tradeReview/scamAlert/qna
    section       VARCHAR(20)  NOT NULL,            -- official/community/qna (작성 시 type에서 도출·검증)
    title         VARCHAR(200) NOT NULL,
    content       TEXT         NOT NULL,
    author_id     VARCHAR(50)  NOT NULL,            -- users.user_id (닉네임은 DTO에서 batch 조회)
    is_pinned     BOOLEAN      NOT NULL DEFAULT FALSE,
    is_answered   BOOLEAN      NOT NULL DEFAULT FALSE,  -- Q&A
    view_count    INTEGER      NOT NULL DEFAULT 0,   -- 0 유지(조회수 증가=쓰기 슬라이스). 1A는 그대로 0 노출.
    like_count    INTEGER      NOT NULL DEFAULT 0,   -- 0 유지(좋아요 테이블/토글=좋아요 슬라이스). 1A는 0 노출.
    -- comment_count: 비정규화 컬럼은 ★1A에 두지 않는다★(유지할 writer 없음 → stale). 1A는 board_comments 에서
    --   라이브 집계(§4). 비정규화 컬럼은 댓글등록 슬라이스에서 maintainer 와 함께 추가.
    status        VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE/HIDDEN (모더레이션)
    created_at    TIMESTAMP    NOT NULL,
    updated_at    TIMESTAMP,
    deleted_at    TIMESTAMP                          -- 소프트삭제(NULL=노출)
);
CREATE INDEX IF NOT EXISTS idx_board_posts_section ON board_posts(section, is_pinned DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_board_posts_type    ON board_posts(type, created_at DESC);
-- idx_board_posts_author 는 1A 읽기 경로(섹션/타입/핀/시간)에서 안 쓰이므로 제외. '내 글' 경로 생기는 슬라이스에서 추가.

CREATE TABLE IF NOT EXISTS board_comments (
    comment_id        VARCHAR(50) PRIMARY KEY,
    post_id           VARCHAR(50) NOT NULL,          -- → board_posts.post_id (논리 FK)
    parent_comment_id VARCHAR(50),                   -- NULL=최상위, 값=1단 답글(부모는 반드시 최상위)
    author_id         VARCHAR(50) NOT NULL,
    content           TEXT        NOT NULL,
    is_admin          BOOLEAN     NOT NULL DEFAULT FALSE,
    is_accepted       BOOLEAN     NOT NULL DEFAULT FALSE,  -- Q&A 채택
    created_at        TIMESTAMP   NOT NULL,
    deleted_at        TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_board_comments_post   ON board_comments(post_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_board_comments_parent ON board_comments(parent_comment_id);
```

### 롤백 SQL (`back/sql/board_read_rollback.sql`)
```sql
DROP TABLE IF EXISTS board_comments;
DROP TABLE IF EXISTS board_posts;
```
적용/롤백은 **로컬 격리 DB에서만 먼저 검증**. prod 적용은 별도 승인.

## 3. 엔티티 (설계 — 구현은 승인 후)
- `domain/board/BoardPost.java` `@Entity @Table(name="board_posts")` — Inquiry 패턴(@Getter, @Builder, @PrePersist로 created_at/status 기본값).
- `domain/board/BoardComment.java` 동일 패턴.
- `BoardPostRepository`, `BoardCommentRepository` (Spring Data JPA).
- enum은 String 컬럼(Inquiry status 방식) — 마이그/DTO에서 프론트 토큰 그대로.

## 4. API 계약 (읽기 전용, `ReturnData<T>` 래퍼)
**GET `/api/board/posts`** — 목록(페이지)
- query: `section?`, `type?`, `page=0`, `size=20`(**기본 20, 최대 50** — 초과 시 50 clamp, 0 이하 무시)
- 정렬: **`is_pinned DESC, created_at DESC, post_id DESC`**(고유 보조키 post_id로 동일 시각 데이터 페이지 중복·누락 방지)
- 필터: `deleted_at IS NULL AND status='ACTIVE'` (+차단 author 제외, §6)
- 응답: `ReturnData.success({ content:[BoardPostSummary], page, size, totalElements, totalPages })`
- `BoardPostSummary` = {id, type, title, body, author, createdAt, viewCount, likeCount, isPinned, isAnswered, commentCount}
- **commentCount = 라이브 집계**(★Codex blocker①): 비정규화 컬럼 없음 → `board_comments`에서 `post_id`별 `COUNT(deleted_at IS NULL)` 서브쿼리/GROUP BY로 산출. 목록 N+1 방지 = 한 쿼리 집계 후 맵 조인.
- **section/type 충돌 거부**(★Codex nit): `type`이 준 `section`에 속하지 않으면 400(빈 페이지 silent 반환 금지).

**GET `/api/board/posts/{postId}`** — 상세 (+댓글 트리)
- **404 규칙**: 미존재 / `deleted_at IS NOT NULL` / `status<>'ACTIVE'`(숨김) 게시글은 **모두 404**(존재 여부 비노출). 차단 author 글도 해당 viewer에겐 404.
- 응답: `BoardPostDetail` = Summary + `comments:[BoardComment{ id, author, body, createdAt, isAdmin, isAccepted, replies:[BoardComment] }]`
- 댓글: `post_id`로 일괄 로드 후 부모/답글 2계층(1단) 조립. **삭제댓글 처리(★Codex blocker②)**: `deleted_at`이 있고 **답글이 달린** 댓글은 **온전한 placeholder 노드**로 반환(원본 `comment_id`·`createdAt` 유지, `author`="(삭제됨)"·`body`="삭제된 댓글입니다"·`isAdmin/isAccepted=false`) — 프론트 `BoardComment`가 non-null `id/author/body/createdAt`를 요구하므로 필드 누락/`null` 금지. 답글 없는 삭제 댓글은 응답에서 제외.
- **조회수 증가 없음**(순수 read). view 증가는 쓰기 슬라이스(POST /view, 1인1회 = trade_post_views 패턴 재사용).

**author 표시(N+1 방지, ★Codex nit)**: post.author_id **+ 모든 댓글·답글의 author_id**를 distinct 수집 → users 1회 batch 조회(InquiryAdminController 패턴)로 닉네임 맵 구성 후 주입. 관리자 타입(notice/event/patch)은 표시명 `운영팀` 고정.

**인증**: 읽기는 공개. 단 차단 필터를 위해 `extractUserId`(옵셔널) — 토큰 있으면 viewerId로 차단 author 제외, 없으면 전체 노출.

## 5. 권한
- 읽기: 누구나 ACTIVE·비삭제 게시글. HIDDEN/삭제/차단 author는 뷰어에서 제외.
- 관리자 조회(숨김·삭제 포함)·작성·삭제는 **이후 슬라이스**.

## 6. 재사용 훅 (이 슬라이스는 "자리만", 실행은 이후)
- **차단(Block)**: 목록/상세 쿼리에 `AND NOT EXISTS (SELECT 1 FROM blocks b WHERE b.blocker_id=:viewerId AND b.blocked_id=board_posts.author_id)` 구조 반영. viewerId 없으면 미적용.
- **신고(Report)**: `ReportController.VALID_TYPES`에 `BOARD_POST`,`BOARD_COMMENT` 추가 + `resolution_action`에 `DELETE_POST` 추가 — **확장 지점만 명시, 구현은 모더레이션 슬라이스.**
- **금칙어(ContentFilter)**: `NicknameValidator` 단어목록 공용화 — **쓰기 슬라이스.**

## 7. 1A 범위 밖 (명시적 제외)
글쓰기/수정/삭제 · 댓글·답글 등록 · 좋아요 토글 · 조회수 증가 · 신고/차단 실행 · 금칙어 · 관리자 작성/모더레이션 · 프론트 API 연결(1B) · prod DB 적용/배포.

## 8. 검증 계획
**마이그레이션 안전성**:
- migration SQL + rollback SQL 먼저 작성.
- **로컬 격리 DB**(전용 throwaway DB — dev DB `pokemon_card_db` 오염 금지)에서 **적용 → catalog 검증(information_schema 로 테이블·컬럼·인덱스 확인) → 롤백(잔존 0 확인) → 재적용** 실제 실행.
- prod DB 적용·서버 배포 **금지**. 향후 prod 적용 전 **DB 백업 + 복원 경로 검증** 필수(백업선행 원칙).
**테스트**(@DataJpaTest + 컨트롤러 통합):
- 익명 조회 / 로그인 조회 / 차단 사용자 제외 / section·type 불일치 400 / 삭제 댓글 placeholder / 삭제·숨김·미존재 게시글 404 / **동일 createdAt 페이지네이션 안정성(post_id 보조키)**.
- N+1 없음 확인(EXPLAIN 또는 repository 테스트의 발행 쿼리 수 검증).
- ddl-auto=validate 부팅 검증(엔티티↔테이블 일치).

## 9. 검증 결과 (2026-06-23, 통합 전 게이트)
- **게이트1 재현성**: `application-boardtest.properties` 환경변수화(`BOARD_TEST_DB_URL/USER/PASSWORD`) +
  `spring.sql.init` 가 **실제 마이그(blocks_migration.sql + board_read_migration.sql)** 를 부팅 시 자동 적용.
  **빈 board_test 에서 BUILD SUCCESSFUL** 로 사람 수기 스키마 적용 의존 제거 실증. (Docker 가용 시 Testcontainers 가
  이상적이나 현재 오프라인이라 의존성 미추가 — 환경변수+자동적용으로 대체.)
- **게이트2 validate**: 테스트 프로필 `ddl-auto=validate` 로 전환 → 스크립트 선행 적용 후 엔티티↔테이블
  검증 통과(빈 DB 부팅 성공이 곧 검증 통과). **board 엔티티↔board_posts/board_comments 일치 확인.**
- **게이트3 N+1**: `feed_query_count_is_constant_regardless_of_post_count` — Hibernate Statistics 로 게시글
  5→20 증가 시 피드 쿼리 수 **불변**(≤2, per-row 0) + 댓글수 집계 **단일 IN 쿼리** 증명.
- **게이트4 전체 회귀** `./gradlew test`: board 테스트 **20개 전부 통과**. 유일 실패 =
  `BackApplicationTests.contextLoads` 가 **`missing column [active_chat_room_id] in table [buy_orders]`**
  (board 무관·커밋된 마이그 없음 = **로컬 dev DB의 기존 drift**, board 추가 전부터 이 환경에서 red).
  board 테이블은 full validate 를 통과(에러가 board 를 지나 buy_orders 에서 발생) → **board 회귀 0**.
  full-green 은 dev DB 를 dev 브랜치 기대 스키마로 정렬해야(별도 env 정비, board 범위 밖).
- **page < 0 → 400** 명시 처리(테스트 포함). 숨김/삭제/미존재/차단 상세는 **동일 404 형태**(`ResponseStatusException(NOT_FOUND, "게시글을 찾을 수 없습니다.")`).
- **CHECK 제약 결정**: type/section/status DB CHECK 는 **읽기 슬라이스에선 미도입**(앱이 행을 삽입하지 않음 →
  실익 0, inquiries.status 선례도 무제약). 작성 슬라이스에서 BoardTaxonomy 검증과 함께 재검토.
- **dev DB 정리**: 진단 중 board 마이그를 pokemon_card_db 에 임시 적용했다가 **롤백으로 원복**(잔존 0).
  진단용으로 돌린 trade/buy_order 채팅 마이그는 객체 선존재로 **전부 no-op** → **dev DB 순변경 0**.
  격리 `board_test` 는 테스트용으로 유지(운영·개발 DB와 별개, 본 문서로 식별).
```
