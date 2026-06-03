-- 스캔 모델(FAISS 인덱스) 재학습 job — 메타몽식 맥북 agent 오케스트레이션 (docs/IMAGE_DATA_STRATEGY.md FF1).
-- 무중단 blue-green: 학습 중 서버는 OLD 인덱스 서빙, TRAINED 후 명시적 DEPLOY 시에만 원자 스왑.
-- 상태: REQUESTED → TRAINING(맥 claim) → TRAINED(staging 업로드) → DEPLOYING → DEPLOYED / FAILED
CREATE TABLE scan_train_jobs (
    job_id           VARCHAR(50)  PRIMARY KEY,
    status           VARCHAR(20)  NOT NULL,
    staged_index_key TEXT,                       -- S3 staging key (학습된 인덱스 아티팩트, TRAINED 시 set)
    sample_count     INT,                        -- 학습에 포함한 캡처 수
    message          TEXT,                       -- 에러/메모
    requested_by     VARCHAR(50),                -- admin user_id
    requested_at     TIMESTAMP    NOT NULL DEFAULT now(),
    trained_at       TIMESTAMP,
    deployed_at      TIMESTAMP
);

CREATE INDEX idx_scan_train_jobs_status ON scan_train_jobs (status);
CREATE INDEX idx_scan_train_jobs_requested ON scan_train_jobs (requested_at DESC);
