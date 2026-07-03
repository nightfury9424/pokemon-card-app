package com.fury.back.auth;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Collections;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 게시판 admin 도메인의 관리자 권한 판정 컴포넌트.
 *
 * <p>도메인 서비스(BoardAdminService)가 웹 필터({@link AdminAllowlistFilter})에 **직접 의존하지 않도록**
 * 분리한 독립 컴포넌트. 기존 공용 필터는 변경하지 않는다(머지 시 기존 admin 기능 회귀 리스크 최소화).
 * allowlist 설정({@code app.admin.user-ids})·enforce 토글({@code app.admin.auth-enabled})은 필터와
 * **동일한 키**를 읽으므로 판정 결과가 발산하지 않는다(설정 단일 진실원=동일 config 키).
 *
 * <p>D-7 임시 게이트: ROLE_ADMIN 풀구현 전 단계. 출시 후 JWT role claim 전환 시 필터와 함께 교체.
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
