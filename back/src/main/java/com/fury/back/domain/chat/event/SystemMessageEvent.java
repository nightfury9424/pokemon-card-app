package com.fury.back.domain.chat.event;

import com.fury.back.domain.chat.dto.ChatMessageDto;

/**
 * Bundle 2-C: 시스템 메시지 저장 후 발행. {@code @TransactionalEventListener(AFTER_COMMIT)}로
 * commit 확정 후 STOMP broadcast — DB 반영 실패 시 메시지만 먼저 퍼지는 위험 차단.
 *
 * <p>topic: {@code /topic/room/{roomId}} (일반 메시지와 동일 — 클라이언트가 messageType으로 분기)
 */
public record SystemMessageEvent(String roomId, ChatMessageDto message) {}
