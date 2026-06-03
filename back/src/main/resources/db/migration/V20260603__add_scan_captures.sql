-- 스캔 데이터 수집 (docs/IMAGE_DATA_STRATEGY.md)
-- 한 번의 스캔 = (A)한국 카드 실사진 + (B)스캔 라벨 데이터 동시 생성.
-- 용도: FAISS multi-ref 보강(매칭정확도) + 카탈로그 이미지 교체(scrydex moat).
-- FK 제약은 코드베이스 관례(asset_images 등 무FK, 앱-관리) 따라 생략.
CREATE TABLE scan_captures (
    capture_id           VARCHAR(50)  PRIMARY KEY,
    user_id              VARCHAR(50),                       -- 탈퇴 시 NULL de-id 가능하도록 nullable
    card_id              VARCHAR(50)  NOT NULL,
    s3_key               TEXT         NOT NULL,
    source_type          VARCHAR(20)  NOT NULL DEFAULT 'SCAN',  -- SCAN | ASSET_PHOTO(FF)
    match_confidence     REAL,                              -- FAISS score (0~1)
    image_quality        SMALLINT,                          -- NULL=미평가, 0~100 (서버 배치 채움)
    blur_score           REAL,                              -- 라플라시안 분산 (배치 채움)
    is_catalog_candidate BOOLEAN      NOT NULL DEFAULT FALSE,
    is_faiss_indexed     BOOLEAN      NOT NULL DEFAULT FALSE,
    consent_version      VARCHAR(16),                       -- ToS 동의 버전 스냅샷 (PIPA)
    created_at           TIMESTAMP    NOT NULL DEFAULT now(),
    deleted_at           TIMESTAMP                          -- soft delete (탈퇴/품질미달)
);

-- 카드별 수집 현황(cap 체크 + 커버리지) / 미인덱스·후보 부분 인덱스(배치·큐레이션 쿼리).
CREATE INDEX idx_scan_captures_card ON scan_captures (card_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_scan_captures_unindexed ON scan_captures (is_faiss_indexed)
    WHERE is_faiss_indexed = FALSE AND deleted_at IS NULL;
CREATE INDEX idx_scan_captures_candidate ON scan_captures (is_catalog_candidate)
    WHERE is_catalog_candidate = TRUE AND deleted_at IS NULL;
