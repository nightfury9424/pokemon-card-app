-- 게시글 조회수 + 게시판 알림 dedup 롤백 (2026-06-27)
-- additive 역순. board_post_views drop, notifications.dedup_key drop. 기존 알림/게시글 데이터 보존.
BEGIN;
DROP INDEX IF EXISTS uq_notifications_dedup;
ALTER TABLE notifications DROP COLUMN IF EXISTS dedup_key;
DROP TABLE IF EXISTS board_post_views;
COMMIT;
