package com.fury.back.common.moderation;

import com.fury.back.common.ReturnData;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 금칙어 위반 전용 매핑 → HTTP 403 + body code=CONTENT_POLICY_VIOLATION.
 * (HTTP 상태와 ReturnData.status='fail' 일관 — IllegalArgumentException→HTTP200 풋건 회피.)
 *
 * <p>★{@code @Order(HIGHEST_PRECEDENCE)}: GlobalExceptionHandler 의
 * {@code @ExceptionHandler(Exception.class)} catch-all(HTTP 200 반환)이 ContentPolicyViolationException 을
 * 먼저 삼키지 못하도록, 이 advice 가 항상 먼저 소비되게 운영 순서를 결정적으로 고정한다(등록 순서 의존 제거).
 * GlobalExceptionHandler 는 미접촉.
 */
@Order(Ordered.HIGHEST_PRECEDENCE)
@RestControllerAdvice
public class ModerationExceptionHandler {

    public static final String CODE = "CONTENT_POLICY_VIOLATION";

    @ExceptionHandler(ContentPolicyViolationException.class)
    public ResponseEntity<ReturnData<?>> handle(ContentPolicyViolationException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(ReturnData.fail(CODE, e.getMessage()));
    }
}
