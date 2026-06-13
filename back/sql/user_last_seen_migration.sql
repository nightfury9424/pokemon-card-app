-- 2026-06-13 유저 활동 추적: users.last_seen_at
-- 용도: 대시보드 "오늘 접속(DAU)" + "접속중(최근 5분)" 집계. 인증 요청 시 throttled(60s) 갱신.
-- 가입(created_at)과 별개. 배포 후부터 쌓임(과거치 없음, 기존 행은 NULL).
--
-- ★배포 순서 필수 (ddl-auto=validate):
--   1) 이 ALTER 를 먼저 실행 (점검 모드 중, 백엔드 내린 상태)
--   2) 그 다음 새 백엔드 배포 → 엔티티 검증 통과
--   거꾸로 하면 새 백엔드가 컬럼 없어서 기동 실패.
--
-- 멱등: IF NOT EXISTS 라 재실행 안전.

ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMP;
