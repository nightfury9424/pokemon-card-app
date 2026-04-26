package com.fury.back.domain.chat.dto;

import lombok.Getter;
import lombok.NoArgsConstructor;

@Getter
@NoArgsConstructor
public class SendMessageRequest {
    private String message;
    private String senderUserId;  // WebSocket에서 인증 대신 클라이언트가 전달
}
