-- 게시판 읽기 토대 롤백 (Slice 1A). board_read_migration.sql 역순.
-- comments 가 posts 를 논리참조하므로 comments 먼저 DROP.
DROP TABLE IF EXISTS board_comments;
DROP TABLE IF EXISTS board_posts;
