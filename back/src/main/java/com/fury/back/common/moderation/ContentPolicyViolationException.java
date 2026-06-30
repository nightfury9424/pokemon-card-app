package com.fury.back.common.moderation;

/**
 * 사용자 작성 콘텐츠 금칙어 위반. 전용 advice 가 HTTP 403 + code=CONTENT_POLICY_VIOLATION 으로 매핑.
 * 메시지는 사용자 표시용 고정 문구만(탐지된 단어/원문 미포함).
 */
public class ContentPolicyViolationException extends RuntimeException {
    public ContentPolicyViolationException(String message) {
        super(message);
    }
}
