-- 경고(warning) 누적 → 자동 정지 모더레이션 (신고 처리용).
-- 활성 경고 수가 임계치(app.moderation.warning-threshold, 기본 3) 도달 시 자동 정지.
CREATE TABLE user_warnings (
    warning_id  VARCHAR(50)  PRIMARY KEY,
    user_id     VARCHAR(50)  NOT NULL,
    reason      VARCHAR(200) NOT NULL,
    report_id   VARCHAR(50),
    issued_by   VARCHAR(50)  NOT NULL,
    created_at  TIMESTAMP    NOT NULL DEFAULT now(),
    revoked_at  TIMESTAMP
);
CREATE INDEX idx_user_warnings_active ON user_warnings (user_id) WHERE revoked_at IS NULL;
