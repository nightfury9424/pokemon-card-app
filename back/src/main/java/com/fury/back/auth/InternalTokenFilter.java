package com.fury.back.auth;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * /api/internal/** 경로 token 검증 filter.
 *
 * <p>nginx에서 외부 차단 + 이 filter에서 X-Internal-Admin-Token 검증 (defense in depth).
 * proxy 뒤 remoteAddr=127.0.0.1 위장 가능하므로 IP만으로 신뢰하지 않는다.
 *
 * <p>token 미설정 (빈 문자열) 시 모든 internal 요청 403 — fail-closed.
 * 비교는 MessageDigest.isEqual (timing-safe).
 */
@Component
public class InternalTokenFilter extends OncePerRequestFilter {

    private static final String HEADER = "X-Internal-Admin-Token";
    private static final String PATH_PREFIX = "/api/internal/";

    private final byte[] expectedTokenBytes;
    private final boolean enabled;

    public InternalTokenFilter(@Value("${app.internal.admin-token:}") String token) {
        if (token == null || token.isBlank()) {
            this.expectedTokenBytes = new byte[0];
            this.enabled = false;
        } else {
            this.expectedTokenBytes = token.getBytes(StandardCharsets.UTF_8);
            this.enabled = true;
        }
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        String path = request.getRequestURI();
        if (path != null && path.startsWith(PATH_PREFIX)) {
            if (!enabled || !isValidToken(request.getHeader(HEADER))) {
                response.setStatus(HttpServletResponse.SC_FORBIDDEN);
                response.setContentType("application/json");
                response.getWriter().write("{\"error\":\"forbidden\"}");
                return;
            }
        }
        filterChain.doFilter(request, response);
    }

    private boolean isValidToken(String provided) {
        if (provided == null || provided.isEmpty()) return false;
        byte[] providedBytes = provided.getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expectedTokenBytes, providedBytes);
    }
}
