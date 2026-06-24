-- 게시글 이미지 첨부 (슬라이스 3). ★정식 마이그 — IF NOT EXISTS 미사용(이름충돌을 성공으로 숨기지 않음).
-- 적용: preflight(아래 테이블/제약/인덱스 부재 확인) → 단일 트랜잭션 + ON_ERROR_STOP. S3 키만 저장(바이너리/base64/전체URL 금지).
-- preflight 예: SELECT to_regclass('public.board_image_uploads'), to_regclass('public.board_post_images'); → 둘 다 NULL 이어야.

-- 1) 임시 업로드(소유권·일회성·만료). 작성 전 S3 에 올린 미연결 이미지.
--    S3 키는 불투명: uploads/board/pending/{uploadId}.jpg (uploaderId 미포함, 소유권은 uploader_id 로만).
CREATE TABLE board_image_uploads (
    upload_id        VARCHAR(50)  PRIMARY KEY,
    uploader_id      VARCHAR(50)  NOT NULL,
    storage_key      TEXT         NOT NULL UNIQUE,
    status           VARCHAR(20)  NOT NULL,                  -- PENDING | CONSUMED
    created_at       TIMESTAMP    NOT NULL DEFAULT now(),
    expires_at       TIMESTAMP    NOT NULL,                  -- created_at + 24h
    consumed_at      TIMESTAMP,
    consumed_post_id VARCHAR(50),
    CONSTRAINT ck_board_image_uploads_status CHECK (status IN ('PENDING', 'CONSUMED'))
);
CREATE INDEX idx_board_image_uploads_pending_expiry ON board_image_uploads(status, expires_at);
CREATE INDEX idx_board_image_uploads_uploader       ON board_image_uploads(uploader_id);

-- 2) 게시글에 연결된 이미지(순서). storage_key 전역 유니크 + 순번 0..4(최대 5장, 서비스도 재검증).
CREATE TABLE board_post_images (
    image_id    VARCHAR(50) PRIMARY KEY,
    post_id     VARCHAR(50) NOT NULL,
    storage_key TEXT        NOT NULL,
    sort_order  INTEGER     NOT NULL,
    created_at  TIMESTAMP   NOT NULL DEFAULT now(),
    CONSTRAINT fk_board_post_images_post FOREIGN KEY (post_id)
        REFERENCES board_posts(post_id) ON DELETE CASCADE,    -- 하드삭제 안전망(soft-delete 는 보존)
    CONSTRAINT uq_board_post_images_order       UNIQUE (post_id, sort_order),
    CONSTRAINT uq_board_post_images_storage_key UNIQUE (storage_key),
    CONSTRAINT ck_board_post_images_sort_order  CHECK (sort_order BETWEEN 0 AND 4)
);
CREATE INDEX idx_board_post_images_post ON board_post_images(post_id, sort_order);
