package com.fury.back.common.moderation;

import com.fury.back.common.ReturnData;
import org.junit.jupiter.api.Test;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 공용 금칙어 검사 게이트. 순수 matches()/failClosedRequired() 로 결정적 검증(파일/스프링 무관).
 * ★정책: 오탐 방지 우선. 점·특수문자·제로폭·반복 우회는 차단, 공백 우회("시 발")는 정상문("도시 발전")
 * 오탐과 충돌하므로 1차 미차단. allowlist 는 sentinel 마스킹(결합 오탐/우회 방지).
 * 테스트 문자열은 최소만 사용.
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

    @Test void dot_special_evasion_detected() {
        assertThat(v("시.발")).isTrue();
        assertThat(v("시*발")).isTrue();
        assertThat(v("시-발")).isTrue();
    }

    @Test void zero_width_evasion_detected() {
        assertThat(v("시​발")).isTrue(); // ZWSP
        assertThat(v("시﻿발")).isTrue();
    }

    @Test void repeated_char_evasion_detected() {
        assertThat(v("개새끼끼끼")).isTrue(); // 과도 반복 축약
    }

    @Test void cross_word_space_NOT_false_positive() {
        // ★오탐 방지: 공백을 제거하지 않으므로 인접 단어 결합 오탐 없음.
        assertThat(v("서울시 발표가 있었어요")).isFalse(); // "서울시"+"발표" ≠ 시발
        assertThat(v("도시 발전 계획")).isFalse();
        assertThat(v("오늘 시세 발표")).isFalse();
        assertThat(v("안녕하세요 좋은 카드네요")).isFalse();
    }

    @Test void pure_space_evasion_not_caught_by_design() {
        // 공백 우회는 정상문 오탐과 충돌 → 1차 미차단(오탐 우선). 운영 신고/큐레이션으로 보강 예정.
        assertThat(v("시 발")).isFalse();
    }

    @Test void allowlist_masks_with_sentinel_no_join() {
        // '시발점'(정상어) 단독 통과.
        assertThat(ContentPolicyService.matches("이번 프로젝트의 시발점", BAD, NONE)).isTrue();  // 미적용 시 탐지
        assertThat(ContentPolicyService.matches("이번 프로젝트의 시발점", BAD, Set.of("시발점"))).isFalse(); // 마스킹
        // 정상어 뒤에 실제 금칙어가 붙으면 차단(마스킹이 금칙어를 가리지 않음).
        assertThat(ContentPolicyService.matches("시발점시발", BAD, Set.of("시발점"))).isTrue();
        // 정상어 앞에 금칙어가 붙어도 차단.
        assertThat(ContentPolicyService.matches("시발시발점", BAD, Set.of("시발점"))).isTrue();
        // sentinel 이 좌우 결합을 막아 새 금칙어 오탐 없음(정상어가 가운데 끼어도 결합 안 됨).
        assertThat(ContentPolicyService.matches("마시발점이", BAD, Set.of("시발점"))).isFalse();
    }

    @Test void empty_inputs_safe() {
        assertThat(ContentPolicyService.matches(null, BAD, NONE)).isFalse();
        assertThat(ContentPolicyService.matches("", BAD, NONE)).isFalse();
        assertThat(ContentPolicyService.matches("아무 말", NONE, NONE)).isFalse(); // 빈 banned
    }

    @Test void nfkc_lowercase_normalized() {
        assertThat(ContentPolicyService.matches("FUCK", Set.of("fuck"), NONE)).isTrue();
        assertThat(ContentPolicyService.matches("ＦＵＣＫ", Set.of("fuck"), NONE)).isTrue(); // 전각 NFKC
    }

    @Test void fail_closed_only_in_non_local_test_profiles() {
        // 운영(비 local/test) + 빈 목록 → 부팅 실패 필요.
        assertThat(ContentPolicyService.failClosedRequired("prod", true)).isTrue();
        assertThat(ContentPolicyService.failClosedRequired("staging", true)).isTrue();
        // local/test/citest/boardtest 또는 목록 있음 → 부팅 허용.
        assertThat(ContentPolicyService.failClosedRequired("local", true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired("citest", true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired("boardtest", true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired("prod", false)).isFalse(); // 목록 있으면 OK
    }

    @Test void advice_maps_to_403_and_code() {
        ResponseEntity<ReturnData<?>> res =
                new ModerationExceptionHandler().handle(new ContentPolicyViolationException("x"));
        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(res.getBody().getCode()).isEqualTo("CONTENT_POLICY_VIOLATION");
        assertThat(res.getBody().getStatus()).isEqualTo("fail");
    }
}
