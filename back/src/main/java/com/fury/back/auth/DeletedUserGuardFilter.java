package com.fury.back.auth;

import com.fury.back.domain.user.User;
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
import java.util.Optional;

/**
 * 탈퇴(deletedAt != null) 계정의 인증 API 호출 차단. 401 + code "USER_DELETED" 반환.
 *
 * 필터 순서: JwtAuthFilter 다음 → 이 필터 → OnboardingGuardFilter.
 *  - 비로그인(authentication=null) 요청은 통과 — JwtAuthFilter가 이미 처리.
 *  - 인증 통과한 요청만 DB로 user 조회.
 *
 * App Review 5.1.1 대응: 탈퇴 후 JWT 만료까지 유효하더라도 즉시 차단.
 *
 * 성능: 매 인증 요청마다 1 DB lookup. 부하 시 캐싱(Caffeine 등) 도입 검토 — follow-up.
 */
@Component
@RequiredArgsConstructor
public class DeletedUserGuardFilter extends OncePerRequestFilter {

    private final UserRepository userRepository;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        Authentication auth = SecurityContextHolder.getContext().getAuthentication();
        if (auth == null || !auth.isAuthenticated() || auth.getPrincipal() == null) {
            filterChain.doFilter(request, response);
            return;
        }
        String userId = auth.getName();
        Optional<User> userOpt = userRepository.findById(userId);
        if (userOpt.isEmpty() || userOpt.get().getDeletedAt() != null) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write(
                    "{\"success\":false,\"message\":\"탈퇴한 계정입니다\",\"code\":\"USER_DELETED\"}");
            return;
        }
        filterChain.doFilter(request, response);
    }
}
