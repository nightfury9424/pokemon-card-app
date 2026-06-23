-- ★★실사용(신고 접수) 시작 후엔 신고 증거 데이터 손실 → 임의 실행 금지·별도 승인 필요.
ALTER TABLE reports DROP COLUMN IF EXISTS reported_snapshot;
