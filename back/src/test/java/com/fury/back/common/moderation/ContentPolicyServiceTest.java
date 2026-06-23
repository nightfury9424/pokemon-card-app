package com.fury.back.common.moderation;

import com.fury.back.common.ReturnData;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 공용 금칙어 검사 게이트. 순수 matches() 로 우회/오탐을 결정적으로 검증(파일/스프링 무관).
 * ★테스트 문자열은 필요한 최소만 사용(원문/공격적 표현 최소화).
 */
class ContentPolicyServiceTest {

    static final Set<String> BAD = Set.of("시발", "개새끼");
    static final Set<String> NONE = Set.of();

    private boolean v(String t) {
        return ContentPolicyService.matches(t, BAD, NONE);
    }

    @Test void exact_banned_detected() {
        assertThat(v("시발")).isTrue();
        assertThat(v("이건 개새끼 같다")).isTrue();
    }

    @Test void spacing_evasion_detected() {
        assertThat(v("시 발")).isTrue();
        assertThat(v("개 새 끼")).isTrue();
    }

    @Test void dot_special_evasion_detected() {
        assertThat(v("시.발")).isTrue();
        assertThat(v("시*발")).isTrue();
    }

    @Test void zero_width_evasion_detected() {
        assertThat(v("시​발")).isTrue(); // ZWSP 삽입
        assertThat(v("시﻿발")).isTrue();
    }

    @Test void repeated_char_evasion_detected() {
        assertThat(v("개새끼끼끼")).isTrue(); // 과도 반복 축약
    }

    @Test void normal_sentence_not_flagged() {
        // '시세 발표'는 시·발 사이 '세'가 있어 compact 에도 '시발' 미포함 → 오탐 X.
        assertThat(v("오늘 시세 발표가 있었어요")).isFalse();
        assertThat(v("안녕하세요 반갑습니다 좋은 카드네요")).isFalse();
    }

    @Test void allowlist_prevents_false_positive() {
        // '시발점'(정상어, starting point)은 '시발' 포함 → allowlist 없으면 오탐.
        assertThat(ContentPolicyService.matches("이번 프로젝트의 시발점", BAD, NONE)).isTrue(); // 미적용 시 오탐
        assertThat(ContentPolicyService.matches("이번 프로젝트의 시발점", BAD, Set.of("시발점"))).isFalse(); // allowlist 소거
    }

    @Test void empty_inputs_safe() {
        assertThat(ContentPolicyService.matches(null, BAD, NONE)).isFalse();
        assertThat(ContentPolicyService.matches("", BAD, NONE)).isFalse();
        assertThat(ContentPolicyService.matches("아무 말", NONE, NONE)).isFalse(); // 빈 banned
    }

    @Test void nfkc_lowercase_normalized() {
        // NFKC: 전각/호환 문자 정규화. lowercase 영문.
        assertThat(ContentPolicyService.matches("FUCK", Set.of("fuck"), NONE)).isTrue();
    }

    @Test void advice_maps_to_403_and_code() {
        ResponseEntity<ReturnData<?>> res =
                new ModerationExceptionHandler().handle(new ContentPolicyViolationException("x"));
        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(res.getBody().getCode()).isEqualTo("CONTENT_POLICY_VIOLATION");
        assertThat(res.getBody().getStatus()).isEqualTo("fail");
    }
}
