-- 신고 당시 원문 immutable snapshot(증거 보존). 자유글은 신고 후 수정 가능하므로 신고 시점 콘텐츠를 보존한다.
-- ★신고 생성 시 1회만 저장, 이후 신고처리·게시글수정·닉네임변경에도 절대 갱신 안 함(immutable).
-- 기존 신고 호환 위해 nullable. additive(기존 테이블 컬럼 추가만). ddl-auto=validate → 배포 전 선적용.
-- prod 적용은 RC 승인 후. 멱등(IF NOT EXISTS).
-- prod(승인 시): docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db < reports_reported_snapshot_migration.sql

ALTER TABLE reports ADD COLUMN IF NOT EXISTS reported_snapshot JSONB;
