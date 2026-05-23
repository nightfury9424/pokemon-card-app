-- =============================================================
-- Chat rooms Phase 1: per-participant hidden_at (방 나가기 + 차단 시 자동 hide)
-- =============================================================
--
-- 정책:
-- - 채팅방 나가기 → 본인의 hidden_at set, DB는 보존 (관리자 조회용)
-- - 차단 시 → 차단한 사람의 hidden_at 자동 set
-- - getMyRooms는 본인의 hidden_at IS NULL 인 방만 노출
-- - sendMessage / getOrCreateRoom 양방향 차단 가드는 그대로
-- - getMessages 가드는 완화 (양쪽 200, UI 비활성화는 conversation-state endpoint로 노출)
--
-- 본 마이그레이션은 nullable + index만 추가. 기존 row 영향 없음.

BEGIN;

ALTER TABLE chat_rooms
    ADD COLUMN IF NOT EXISTS buyer_hidden_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS seller_hidden_at TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_chat_rooms_buyer_visible
    ON chat_rooms (buyer_user_id, buyer_hidden_at);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_seller_visible
    ON chat_rooms (seller_user_id, seller_hidden_at);

COMMIT;
