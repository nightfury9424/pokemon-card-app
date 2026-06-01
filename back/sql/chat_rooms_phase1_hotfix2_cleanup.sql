-- =============================================================
-- Phase 1 hotfix #2 — chat_rooms hidden_at 잔여 데이터 cleanup
-- =============================================================
--
-- 배경:
-- Phase 1A (`4e9de5e3`)에서 notifyBlock 이 차단 액션 시 차단한 사람의
-- hidden_at 을 자동 set 했음. 그러나 사용자 정책 변경으로 Phase 1 hotfix
-- (`e8710211`) 에서 자동 set 제거함. 그러나 이미 prod DB 에 찍힌 hidden_at
-- 값은 그대로 남아있어 다음 현상 발생:
--   - 사용자가 차단 해제했어도 chat list 에 방 미노출 (본인 hidden_at NOT NULL)
--   - 다시 채팅하기 시도 시 getOrCreateRoom 이 상대 hidden_at 보고 403
--     "OTHER_LEFT" 반환 → "연락할 수 없는 사용자입니다" 안내
--
-- 본 cleanup 은 **모든** chat_rooms hidden_at 을 NULL 로 reset.
-- 실제 leaveRoom 으로 나간 사용자도 영향받음 — D-7 출시 전 테스트 단계
-- (실 사용자 nightfury / 본인만) 라서 안전.
-- 출시 후에는 본 script 재실행 금지.

BEGIN;

UPDATE chat_rooms
SET buyer_hidden_at = NULL,
    seller_hidden_at = NULL
WHERE buyer_hidden_at IS NOT NULL
   OR seller_hidden_at IS NOT NULL;

COMMIT;
