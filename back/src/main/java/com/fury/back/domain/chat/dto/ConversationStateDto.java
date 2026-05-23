package com.fury.back.domain.chat.dto;

/**
 * 채팅방 진입/active 시점 conversation 상태.
 *
 * <p>차단 관계에 따라 클라이언트가 입력창 비활성화 + 안내 banner 표시하기 위한 메타.
 *
 * @param canSendMessage 메시지 전송 가능 여부. 한쪽이라도 차단 관계면 false.
 * @param blockNotice    차단 안내 문구. null 이면 표시 안 함.
 */
public record ConversationStateDto(
        boolean canSendMessage,
        String blockNotice
) {}
