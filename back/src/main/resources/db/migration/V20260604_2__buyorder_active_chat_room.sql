-- B2-12: 구매(BuyOrder)를 판매처럼 거래중(예약)→완료 플로우로.
-- 예약 시 선택된 상대(seller)의 chat_room_id 기록 (판매 trade_posts.active_chat_room_id 대칭).
-- 실거래가 정산은 trade_settlements 에 trade_id = buy_order_id 로 저장(별도 마이그 불필요, ID 공간 분리).
ALTER TABLE buy_orders ADD COLUMN IF NOT EXISTS active_chat_room_id VARCHAR(50);
