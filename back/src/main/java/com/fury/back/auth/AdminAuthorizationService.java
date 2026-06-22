package com.fury.back.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Collections;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 관리자 권한 판정 단일 진실원(SSOT).
 *
 * <p>allowlist(`app.admin.user-ids`) 파싱 + 관리자 여부 판정을 한 곳에서 소유한다.
 * 웹 필터({@link AdminAllowlistFilter})와 도메인 서비스(예: 게시판 admin)가 **동일하게** 사용 —
 * 서비스가 웹 필터를 직접 의존하지 않도록 분리(계층 혼선 방지).
 *
 * <p>D-7 임시 게이트: ROLE_ADMIN 풀구현 전 단계. 출시 후 JWT role claim 전환 시 본 컴포넌트를 교체.
 */
@Component
public class AdminAuthorizationService {

    private final Set<String> allowedUserIds;
    private final boolean enforced;

    public AdminAuthorizationService(
            @Value("${app.admin.user-ids:}") String allowlist,
            @Value("${app.admin.auth-enabled:false}") boolean adminAuthEnabled) {
        this.allowedUserIds = (allowlist == null || allowlist.isBlank())
                ? Collections.emptySet()
                : Arrays.stream(allowlist.split(","))
                        .map(String::trim)
                        .filter(s -> !s.isEmpty())
                        .collect(Collectors.toUnmodifiableSet());
        this.enforced = adminAuthEnabled;
    }

    /** userId 가 관리자 allowlist 에 포함되는지. null/미포함 → false(fail-closed). */
    public boolean isAdmin(String userId) {
        return userId != null && allowedUserIds.contains(userId);
    }

    /** 관리자 인증 강제 여부(app.admin.auth-enabled). local default=false(permitAll 편의). */
    public boolean isEnforced() {
        return enforced;
    }

    /** allowlist 크기(비어있음 가드 등). */
    public int allowedCount() {
        return allowedUserIds.size();
    }
}
