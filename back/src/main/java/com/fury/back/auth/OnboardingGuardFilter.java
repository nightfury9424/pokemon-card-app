package com.fury.back.auth;

import com.fury.back.domain.user.UserRepository;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * onboarded=false 사용자의 API 호출을 차단한다. 클라이언트 라우팅만으로는 우회 가능하므로 서버단 가드 필수.
 * 허용 경로(아래 ALLOWED_PREFIXES)를 제외한 모든 인증 요청에 적용.
 */
@Component
@RequiredArgsConstructor
public class OnboardingGuardFilter extends OncePerRequestFilter {

    private final UserRepository userRepository;

    private static final List<String> ALLOWED_PREFIXES = List.of(
            "/api/auth/",
            "/api/users/me",
            "/api/users/onboarding",
            "/api/users/nickname/check",
            "/swagger-ui",
            "/api-docs",
            "/images/",
            "/ws/"
    );

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated() || auth.getPrincipal() == null) {
            filterChain.doFilter(request, response);
            return;
        }

        String path = request.getRequestURI();
        for (String prefix : ALLOWED_PREFIXES) {
            if (path.startsWith(prefix)) {
                filterChain.doFilter(request, response);
                return;
            }
        }

        String userId = auth.getName();
        boolean onboarded = userRepository.findById(userId)
                .map(u -> u.isOnboarded())
                .orElse(false);
        if (!onboarded) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write("{\"success\":false,\"message\":\"온보딩이 필요합니다\",\"code\":\"ONBOARDING_REQUIRED\"}");
            return;
        }

        filterChain.doFilter(request, response);
    }
}
