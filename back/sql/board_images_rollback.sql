-- 롤백: board 이미지 첨부 (board_post_images + board_image_uploads).
-- ★주의: 이미 게시글에 연결된 이미지가 있으면 데이터 손실. 실사용 시작 후엔 별도 판단.
DROP TABLE IF EXISTS board_post_images;
DROP TABLE IF EXISTS board_image_uploads;
