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

    @Test void allowlist_sentinel_prevents_cross_join_in_all_views() {
        // allow 'bc' 마스킹이 좌우 'a','d'를 결합시켜 'ad' 오탐을 만들지 않음(base/punct/collapsed 모두).
        // sentinel 이 제거대상이면 'a'+'d'='ad' 오탐 → 경계 마커가 모든 비교본에서 유지됨을 증명.
        assertThat(ContentPolicyService.matches("abcd", Set.of("ad"), Set.of("bc"))).isFalse();
    }

    @Test void injected_sentinel_char_is_stripped_no_evasion() {
        // 사용자가 경계 마커(U+E000)를 직접 끼워 넣어도 사전 제거 → 금칙어 재결합되어 탐지(우회 불가).
        assertThat(ContentPolicyService.matches("시\uE000발", BAD, NONE)).isTrue();
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

    @Test void fail_closed_uses_exact_profile_match_not_contains() {
        // 운영(비 lenient) + 빈 목록 → 부팅 실패 필요.
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"prod"}, true)).isTrue();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"staging"}, true)).isTrue();
        // ★부분일치 함정: "prod-test"·"production" 은 lenient 아님(contains("test") 금지 확인).
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"prod-test"}, true)).isTrue();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"production"}, true)).isTrue();
        // ★active profile 부재/null = 운영 가정 → fail-closed(무음 비활성화 금지).
        assertThat(ContentPolicyService.failClosedRequired(new String[]{}, true)).isTrue();
        assertThat(ContentPolicyService.failClosedRequired(null, true)).isTrue();
        // 여러 개 중 하나라도 비-lenient → fail-closed.
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"local", "prod"}, true)).isTrue();
        // lenient 정확 일치(대소문자/공백 정규화) → 허용.
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"local"}, true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"test"}, true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"citest"}, true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"boardtest"}, true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"  CITEST "}, true)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"local", "test"}, true)).isFalse();
        // 목록이 있으면 어떤 프로파일이든 OK.
        assertThat(ContentPolicyService.failClosedRequired(new String[]{"prod"}, false)).isFalse();
        assertThat(ContentPolicyService.failClosedRequired(new String[]{}, false)).isFalse();
    }

    @Test void advice_maps_to_403_and_code() {
        ResponseEntity<ReturnData<?>> res =
                new ModerationExceptionHandler().handle(new ContentPolicyViolationException("x"));
        assertThat(res.getStatusCode()).isEqualTo(HttpStatus.FORBIDDEN);
        assertThat(res.getBody().getCode()).isEqualTo("CONTENT_POLICY_VIOLATION");
        assertThat(res.getBody().getStatus()).isEqualTo("fail");
    }
}
