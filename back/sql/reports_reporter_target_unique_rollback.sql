-- reports 중복 신고 방지 인덱스 롤백. 인덱스만 제거(데이터 손실 없음) — snapshot 컬럼 drop 과 달리 안전.
DROP INDEX IF EXISTS uq_reports_reporter_target;
