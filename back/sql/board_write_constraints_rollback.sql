-- 게시판 쓰기 CHECK 롤백 (Slice 2).
ALTER TABLE board_posts DROP CONSTRAINT IF EXISTS chk_board_posts_type_section;
ALTER TABLE board_posts DROP CONSTRAINT IF EXISTS chk_board_posts_status;
