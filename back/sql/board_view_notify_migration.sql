-- 게시글 조회수 + 게시판 알림 dedup 마이그레이션 (2026-06-27)
-- forward. additive only — 기존 데이터 0 영향. backfill 없음(배포 후 신규 조회부터 집계).
BEGIN;

-- 1) 게시글 조회 기록 — (post_id, viewer_id) 복합 PK = 1인 1조회. 작성자/숨김/삭제 제외는 서비스 처리.
CREATE TABLE IF NOT EXISTS board_post_views (
    post_id   VARCHAR(50) NOT NULL,
    viewer_id VARCHAR(50) NOT NULL,
    viewed_at TIMESTAMP   NOT NULL DEFAULT now(),
    PRIMARY KEY (post_id, viewer_id),
    CONSTRAINT fk_bpv_post   FOREIGN KEY (post_id)   REFERENCES board_posts(post_id) ON DELETE CASCADE,
    CONSTRAINT fk_bpv_viewer FOREIGN KEY (viewer_id) REFERENCES users(user_id)       ON DELETE CASCADE
);

-- 2) 알림 멱등 dedup — 좋아요/댓글/대댓글 중복 알림 방지. 기존 행은 dedup_key NULL(영향 0).
ALTER TABLE notifications ADD COLUMN IF NOT EXISTS dedup_key VARCHAR(180);
CREATE UNIQUE INDEX IF NOT EXISTS uq_notifications_dedup
    ON notifications(dedup_key) WHERE dedup_key IS NOT NULL;

COMMIT;
