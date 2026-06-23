-- 게시판 쓰기 슬라이스 무결성 CHECK (Slice 2). 쓰기 시작 → DB 레벨 방어(수동 SQL·버그로 잘못된 행 차단).
-- ddl-auto=validate → 코드 배포 전 선행 적용(★승인 후). 로컬 격리 검증 전까지 prod 금지.
-- 멱등: 이미 존재하면 스킵.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_board_posts_status') THEN
        ALTER TABLE board_posts ADD CONSTRAINT chk_board_posts_status
            CHECK (status IN ('ACTIVE', 'HIDDEN'));
    END IF;

    -- type 허용값 + section 허용값 + type↔section 매핑을 한 번에 강제.
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'chk_board_posts_type_section') THEN
        ALTER TABLE board_posts ADD CONSTRAINT chk_board_posts_type_section
            CHECK (
                (section = 'official'  AND type IN ('notice', 'event', 'patch'))      OR
                (section = 'community' AND type IN ('free', 'tradeReview', 'scamAlert')) OR
                (section = 'qna'       AND type = 'qna')
            );
    END IF;
END $$;
