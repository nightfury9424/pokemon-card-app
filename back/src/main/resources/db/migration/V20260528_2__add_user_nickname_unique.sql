-- ============================================================================
-- V20260528_2__add_user_nickname_unique.sql
-- ============================================================================
-- 활성 사용자(deleted_at IS NULL)의 닉네임 중복 차단 — Partial UNIQUE INDEX.
--
-- 왜 partial인가:
--  - 탈퇴자(deleted_at != NULL) 닉네임은 "탈퇴한 사용자 #<hash>" 형태로 마스킹됨.
--    동일 hash가 다른 탈퇴자에게 우연히 매칭될 가능성이 있어 unique 제약을 모든 row에 걸면
--    탈퇴 처리 자체가 실패할 수 있음. 탈퇴자는 unique 검사에서 제외.
--  - 활성 사용자끼리만 중복 차단 → 정확히 우리가 원하는 사양.
--
-- LOWER 사용 — application의 NicknameValidator + UserRepository JPA query (LOWER(nickname))
-- 와 정렬. 대소문자 다른 동일 닉네임도 중복으로 차단.
--
-- 사전 조건: 현재 활성 사용자 사이에 중복 닉네임이 없어야 함. 있으면 CREATE UNIQUE INDEX 실패.
-- 사전 확인:
--   SELECT LOWER(nickname), count(*) FROM users WHERE deleted_at IS NULL
--    GROUP BY LOWER(nickname) HAVING count(*) > 1;
-- → 0 row 이어야 정상. 있으면 manual rename 후 진행.
--
-- 적용 방법 (prod):
--   docker exec -i pokefolio-postgres psql -U pokefolio -d pokemon_card_db \
--     < V20260528_2__add_user_nickname_unique.sql
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS uk_users_nickname_active
    ON users (LOWER(nickname))
    WHERE deleted_at IS NULL;
