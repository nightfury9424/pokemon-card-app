package com.fury.back.auth;

import com.fury.back.config.SecurityConfig;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Arrays;
import java.util.Collections;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * /api/admin/** (+ price admin 경로) 사전 게이트.
 *
 * <p>D-7 임시 게이트: ROLE_ADMIN 풀구현 전 단계로 userId allowlist 만으로 보호.
 * 출시 후 JWT role claim + ROLE_ADMIN 도입되면 본 필터 제거하고
 * SecurityConfig hasAuthority 분기로 전환.
 *
 * <p>동작:
 * <ul>
 *   <li>app.admin.auth-enabled=false (local default) → bypass</li>
 *   <li>admin path 아님 → bypass</li>
 *   <li>allowlist 비어있음 → 403 (fail-closed, 운영 사고 차단)</li>
 *   <li>SecurityContext userId가 allowlist 포함 → 통과</li>
 *   <li>그 외 → 403 forbidden</li>
 * </ul>
 *
 * <p>JwtAuthFilter 다음에 위치해야 SecurityContext에서 userId 추출 가능.
 */
@Component
public class AdminAllowlistFilter extends OncePerRequestFilter {

    private static final AntPathMatcher MATCHER = new AntPathMatcher();

    private final Set<String> allowedUserIds;
    private final boolean enforced;

    public AdminAllowlistFilter(
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

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        if (!enforced) {
            filterChain.doFilter(request, response);
            return;
        }

        String path = request.getRequestURI();
        if (!matchesAdminPath(path)) {
            filterChain.doFilter(request, response);
            return;
        }

        String userId = currentUserId();
        if (userId == null || !allowedUserIds.contains(userId)) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json");
            response.getWriter().write("{\"error\":\"forbidden\"}");
            return;
        }
        filterChain.doFilter(request, response);
    }

    private boolean matchesAdminPath(String path) {
        if (path == null) return false;
        for (String pattern : SecurityConfig.ADMIN_PATH_PATTERNS) {
            if (MATCHER.match(pattern, path)) return true;
        }
        return false;
    }

    private String currentUserId() {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated()) return null;
        Object principal = auth.getPrincipal();
        return principal instanceof String s ? s : null;
    }
}
