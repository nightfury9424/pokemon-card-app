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
 * 2026-05-29: 정지(suspended_at != null) 계정도 차단 — 403 + code "USER_SUSPENDED" (Codex C).
 *   admin allowlist 사용자는 정지 면제 (Codex K). 단 /api/users/me 는 통과 — 정지 banner 표시용.
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
    private final AdminAuthorizationService adminAuthorizationService;

    /** 정지 사용자도 자기 정보 조회는 통과 — 게이트 사유 표시용. */
    private static final String SUSPENDED_PASSTHROUGH_PATH = "/api/users/me";
    /** 정지 사용자 이의신청 — 이 POST 하나만 allowlist(앱 내 이의신청 가능). 나머지 문의 API 는 계속 차단. */
    private static final String SUSPENSION_APPEAL_PATH = "/api/suspension-appeals";

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
        // 2026-05-29: 정지 사용자 차단 — admin allowlist 면제 + /api/users/me 통과 (banner 표시용).
        User user = userOpt.get();
        if (user.isSuspended() && !adminAuthorizationService.isAdmin(userId)) {
            String path = request.getRequestURI();
            String method = request.getMethod();
            // /me 는 GET 만(정지자가 DELETE /me 로 자기삭제→재가입 밴 회피 차단), 이의신청은 POST 만.
            boolean allowed = (SUSPENDED_PASSTHROUGH_PATH.equals(path) && "GET".equalsIgnoreCase(method))
                    || (SUSPENSION_APPEAL_PATH.equals(path) && "POST".equalsIgnoreCase(method));
            if (!allowed) {
                response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                response.setContentType("application/json;charset=UTF-8");
                response.getWriter().write(
                        "{\"success\":false,\"message\":\"정지된 계정입니다\",\"code\":\"USER_SUSPENDED\"}");
                return;
            }
        }
        filterChain.doFilter(request, response);
    }
}
