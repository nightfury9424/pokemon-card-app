-- 고객 문의 DB 전환 (메일 → DB + 관리자 페이지). ddl-auto=validate 라 배포 전 선행 실행 필수.
-- prod: docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < inquiries_migration.sql
CREATE TABLE IF NOT EXISTS inquiries (
    inquiry_id    VARCHAR(50)  PRIMARY KEY,
    user_id       VARCHAR(50)  NOT NULL,
    category      VARCHAR(30)  NOT NULL,
    title         VARCHAR(200) NOT NULL,
    content       TEXT         NOT NULL,
    contact_email VARCHAR(200),
    status        VARCHAR(20)  NOT NULL DEFAULT 'OPEN',
    created_at    TIMESTAMP    NOT NULL,
    admin_reply   TEXT,
    replied_by    VARCHAR(50),
    replied_at    TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_inquiries_user   ON inquiries(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_inquiries_status ON inquiries(status,  created_at DESC);
