package com.fury.back.auth;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/** 관리자 권한 SSOT 단위 검증. */
class AdminAuthorizationServiceTest {

    @Test
    void parses_allowlist_and_isAdmin() {
        AdminAuthorizationService s = new AdminAuthorizationService("a, b ,c", true);
        assertThat(s.isAdmin("a")).isTrue();
        assertThat(s.isAdmin("b")).isTrue();   // 공백 trim
        assertThat(s.isAdmin("z")).isFalse();
        assertThat(s.isAdmin(null)).isFalse(); // null fail-closed
        assertThat(s.isEnforced()).isTrue();
        assertThat(s.allowedCount()).isEqualTo(3);
    }

    @Test
    void empty_allowlist_fail_closed() {
        AdminAuthorizationService s = new AdminAuthorizationService("", false);
        assertThat(s.isAdmin("a")).isFalse();
        assertThat(s.allowedCount()).isZero();
        assertThat(s.isEnforced()).isFalse();
    }
}
