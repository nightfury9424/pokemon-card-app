package com.fury.back.domain.chat.event;

/**
 * Bundle 1 G1 (2026-05-22) — 채팅방 입장 시 메시지 read 갱신 후 발행.
 * {@code @TransactionalEventListener(phase=AFTER_COMMIT)}로 처리 → DB 반영 확정 후 STOMP broadcast.
 * payload는 sender 측 "내가 보낸 미읽음 메시지 전부 read" 갱신용으로 충분 (messageIds 불필요).
 */
public record ChatReadEvent(String roomId, String readerUserId) {}
