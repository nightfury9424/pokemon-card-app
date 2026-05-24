-- =============================================================
-- Trade active chat room — 거래중 상대 지정 모델
-- =============================================================
--
-- 정책:
-- - RESERVED("거래중") 상태 시 판매자가 선택한 chat_room_id 저장
-- - 선택된 상대만 채팅 가능, 나머지 buyer 는 input 비활성 + 안내
-- - OPEN 으로 복귀 시 active_chat_room_id NULL clear
-- - COMPLETED 시 active_chat_room_id 유지 (선택 상대 후속 대화 가능)
-- - DELETED 시 active_chat_room_id 유지 (어차피 삭제)
--
-- backfill 정책 (사용자 결정 A):
-- - 기존 RESERVED 거래의 active_chat_room_id 는 NULL 유지
-- - 기존 RESERVED 는 "상대 미지정 거래중" 상태로 둠
-- - 사용자가 다시 거래중 변경 시 상대 선택 강제
--
-- FK 는 두지 않음 — chat_rooms 는 hard delete 안 하는 정책 (hidden_at 모델).
-- chat_room_id 가 dangling 될 일 거의 없으므로 단순 nullable VARCHAR 로 충분.

BEGIN;

ALTER TABLE trade_posts
    ADD COLUMN IF NOT EXISTS active_chat_room_id VARCHAR(50);

CREATE INDEX IF NOT EXISTS idx_trade_posts_active_chat_room
    ON trade_posts (active_chat_room_id)
    WHERE active_chat_room_id IS NOT NULL;

COMMIT;
