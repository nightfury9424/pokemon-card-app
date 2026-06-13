-- 2026-06-13 문의 사진 첨부 (모든 카테고리): inquiries.image_keys (storage key CSV, trade.image_url 패턴)
-- ★ddl-auto=validate → 배포 전 이 ALTER 먼저. 멱등.
ALTER TABLE inquiries ADD COLUMN IF NOT EXISTS image_keys TEXT;
