-- 스캔 이미지 수집·활용 선택 동의 (PIPA, docs/IMAGE_DATA_STRATEGY.md).
-- 미동의(false)면 scan_captures 캡처 skip. 기존 유저는 DEFAULT FALSE = 미동의(안전 기본값).
ALTER TABLE users ADD COLUMN scan_image_consent BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN scan_image_consent_at TIMESTAMP;
