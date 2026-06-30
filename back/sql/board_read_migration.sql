-- 게시판 읽기 토대 (Slice 1A). ddl-auto=validate → 코드 배포 전 선행 적용 필수(★승인 후).
-- ★로컬 격리 검증 전용. prod 적용 금지 — 별도 승인 + DB 백업/복원 경로 검증 선행.
-- prod(승인 시): docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < board_read_migration.sql

CREATE TABLE IF NOT EXISTS board_posts (
    post_id     VARCHAR(50)  PRIMARY KEY,
    type        VARCHAR(20)  NOT NULL,            -- notice/event/patch/free/tradeReview/scamAlert/qna
    section     VARCHAR(20)  NOT NULL,            -- official/community/qna (작성 시 type에서 도출·검증)
    title       VARCHAR(200) NOT NULL,
    content     TEXT         NOT NULL,
    author_id   VARCHAR(50)  NOT NULL,            -- users.user_id (닉네임은 DTO에서 batch 조회)
    is_pinned   BOOLEAN      NOT NULL DEFAULT FALSE,
    is_answered BOOLEAN      NOT NULL DEFAULT FALSE,  -- Q&A
    view_count  INTEGER      NOT NULL DEFAULT 0,   -- 0 유지(증가=쓰기 슬라이스)
    like_count  INTEGER      NOT NULL DEFAULT 0,   -- 0 유지(좋아요=쓰기 슬라이스)
    status      VARCHAR(20)  NOT NULL DEFAULT 'ACTIVE',  -- ACTIVE/HIDDEN (모더레이션)
    created_at  TIMESTAMP    NOT NULL,
    updated_at  TIMESTAMP,
    deleted_at  TIMESTAMP                          -- 소프트삭제(NULL=노출)
);

-- 활성 목록 조회 인덱스 — 정렬(is_pinned DESC, created_at DESC, post_id DESC)과 정렬키 일치.
CREATE INDEX IF NOT EXISTS idx_board_posts_feed
    ON board_posts (section, is_pinned DESC, created_at DESC, post_id DESC);
CREATE INDEX IF NOT EXISTS idx_board_posts_type
    ON board_posts (type, created_at DESC);

CREATE TABLE IF NOT EXISTS board_comments (
    comment_id        VARCHAR(50) PRIMARY KEY,
    post_id           VARCHAR(50) NOT NULL,          -- → board_posts.post_id (논리 FK, 앱레벨 무결성)
    parent_comment_id VARCHAR(50),                   -- NULL=최상위, 값=1단 답글(부모는 반드시 최상위)
    author_id         VARCHAR(50) NOT NULL,
    content           TEXT        NOT NULL,
    is_admin          BOOLEAN     NOT NULL DEFAULT FALSE,
    is_accepted       BOOLEAN     NOT NULL DEFAULT FALSE,  -- Q&A 채택
    created_at        TIMESTAMP   NOT NULL,
    deleted_at        TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_board_comments_post
    ON board_comments (post_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_board_comments_parent
    ON board_comments (parent_comment_id);
