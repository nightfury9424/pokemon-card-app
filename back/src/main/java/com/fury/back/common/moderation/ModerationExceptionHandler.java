package com.fury.back.common.moderation;

import com.fury.back.common.ReturnData;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 금칙어 위반 전용 매핑 → HTTP 403 + body code=CONTENT_POLICY_VIOLATION.
 * (HTTP 상태와 ReturnData.status='fail' 일관 — IllegalArgumentException→HTTP200 풋건 회피.)
 * GlobalExceptionHandler 미접촉(별도 advice, 더 구체적 예외 타입이 우선 매칭).
 */
@RestControllerAdvice
public class ModerationExceptionHandler {

    public static final String CODE = "CONTENT_POLICY_VIOLATION";

    @ExceptionHandler(ContentPolicyViolationException.class)
    public ResponseEntity<ReturnData<?>> handle(ContentPolicyViolationException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(ReturnData.fail(CODE, e.getMessage()));
    }
}
