-- 게시판 좋아요 (자유글 type='free' 전용, 1.0.4).
-- ★board_post_likes 가 source of truth — likeCount = COUNT(*). board_posts.like_count 는 legacy/미사용(읽지·쓰지 않음).
-- ddl-auto=validate → 코드 배포 전 선행 적용 필수(★승인 후). 로컬 격리 검증 전까지 prod 금지. 멱등(IF NOT EXISTS).
-- prod(승인 시): docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < board_post_likes_migration.sql

CREATE TABLE IF NOT EXISTS board_post_likes (
    like_id     VARCHAR(50)  PRIMARY KEY,
    post_id     VARCHAR(50)  NOT NULL,           -- board_posts.post_id (논리 FK, 물리 FK 없음 — 기존 board 관례)
    user_id     VARCHAR(50)  NOT NULL,           -- users.user_id (논리 FK)
    created_at  TIMESTAMP    NOT NULL DEFAULT NOW(),
    -- ★중복 좋아요 방지 + 동시성 보장. (post_id, user_id) 선두라 post_id 단독 인덱스 역할도 겸함.
    CONSTRAINT uq_board_post_likes_post_user UNIQUE (post_id, user_id)
);

-- 내 좋아요(viewer 기준) 조회용. post_id 단독 인덱스는 UNIQUE 가 커버하므로 생략.
CREATE INDEX IF NOT EXISTS idx_board_post_likes_user ON board_post_likes(user_id);
