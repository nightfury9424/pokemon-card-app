package com.fury.back.config;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * IP 기반 rate limit + 자동 임시 ban — 무지성 크롤링/스크래핑/브루트포스 차단.
 *
 * <p>per-IP 토큰버킷(분당 충전). auth 경로는 강한 제한, 일반 API는 느슨하지만 사람 한도 초과 시 차단.
 * 한도를 연속으로 넘기면(strike) IP를 일정 시간 ban → 429. nginx 뒤라 X-Forwarded-For 로 실 IP 추출.
 *
 * <p>분산 아님(단일 인스턴스 in-memory). prod 단일 컨테이너 전제. 필요 시 Redis/Bucket4j 로 승격.
 * 토글: app.ratelimit.enabled (기본 true). 한도는 app.ratelimit.* 로 조정.
 */
@Slf4j
@Component
@Order(Ordered.HIGHEST_PRECEDENCE + 10)
public class RateLimitFilter extends OncePerRequestFilter {

    @Value("${app.ratelimit.enabled:true}")
    private boolean enabled;
    /** 일반 API per-IP 분당 허용 (사람은 안 걸리고 크롤러만 걸리는 수준). */
    @Value("${app.ratelimit.general-per-min:600}")
    private int generalPerMin;
    /** 인증 경로(/api/auth/**) per-IP 분당 허용 (브루트포스/계정탐색 차단). */
    @Value("${app.ratelimit.auth-per-min:60}")
    private int authPerMin;
    /** 한도 초과 누적 strike 가 이 수 이상이면 임시 ban. */
    @Value("${app.ratelimit.ban-threshold:8}")
    private int banThreshold;
    /** ban 지속 분. */
    @Value("${app.ratelimit.ban-minutes:10}")
    private long banMinutes;

    private final ConcurrentHashMap<String, Bucket> buckets = new ConcurrentHashMap<>();
    private final ObjectMapper mapper = new ObjectMapper();

    private static final class Bucket {
        double tokens;
        long lastRefillMs;
        int strikes;
        long bannedUntilMs;
        long lastSeenMs;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
            throws ServletException, IOException {
        if (!enabled || isExempt(req)) {
            chain.doFilter(req, res);
            return;
        }
        final boolean auth = req.getRequestURI().startsWith("/api/auth");
        final int capacity = auth ? authPerMin : generalPerMin;
        final String key = clientIp(req) + (auth ? "|a" : "|g");
        final long now = System.currentTimeMillis();

        boolean blocked = false;
        long retryAfterSec = banMinutes * 60;
        Bucket b = buckets.computeIfAbsent(key, k -> {
            Bucket nb = new Bucket();
            nb.tokens = capacity;
            nb.lastRefillMs = now;
            return nb;
        });
        synchronized (b) {
            b.lastSeenMs = now;
            if (now < b.bannedUntilMs) {
                blocked = true;
                retryAfterSec = Math.max(1, (b.bannedUntilMs - now) / 1000);
            } else {
                // 분당 capacity 비율로 토큰 충전 (token bucket).
                double refill = (now - b.lastRefillMs) / 60000.0 * capacity;
                b.tokens = Math.min(capacity, b.tokens + refill);
                b.lastRefillMs = now;
                if (b.tokens >= 1.0) {
                    b.tokens -= 1.0;
                    b.strikes = 0;
                } else {
                    b.strikes++;
                    blocked = true;
                    retryAfterSec = 60;
                    if (b.strikes >= banThreshold) {
                        b.bannedUntilMs = now + banMinutes * 60_000L;
                        retryAfterSec = banMinutes * 60;
                    }
                }
            }
        }

        if (blocked) {
            if (b.bannedUntilMs == now + banMinutes * 60_000L || b.strikes >= banThreshold) {
                log.warn("[RateLimit] IP ban key={} strikes={} {}m", key, b.strikes, banMinutes);
            }
            res.setStatus(429);
            res.setHeader("Retry-After", String.valueOf(retryAfterSec));
            res.setContentType("application/json;charset=UTF-8");
            mapper.writeValue(res.getWriter(), Map.of(
                    "status", "fail", "code", "F429",
                    "message", "요청이 너무 많습니다. 잠시 후 다시 시도해주세요."));
            return;
        }
        chain.doFilter(req, res);
    }

    private boolean isExempt(HttpServletRequest req) {
        if ("OPTIONS".equalsIgnoreCase(req.getMethod())) return true; // CORS preflight
        String p = req.getRequestURI();
        return p.startsWith("/api/health")
                || p.startsWith("/api/internal")   // nginx 외부 차단 + InternalTokenFilter
                || p.startsWith("/images")
                || p.startsWith("/ws")
                || p.startsWith("/swagger-ui")
                || p.startsWith("/api-docs");
    }

    /**
     * 실 클라이언트 IP. prod nginx 가 X-Real-IP=$remote_addr 로 덮어씀(스푸핑 불가) → 최우선.
     * fallback: X-Forwarded-For 의 <b>마지막</b> 홉(nginx 가 append 한 실주소; 앞부분은 클라 위조 가능) → remoteAddr.
     */
    private String clientIp(HttpServletRequest req) {
        String real = req.getHeader("X-Real-IP");
        if (real != null && !real.isBlank()) return real.trim();
        String xff = req.getHeader("X-Forwarded-For");
        if (xff != null && !xff.isBlank()) {
            int comma = xff.lastIndexOf(',');
            return (comma >= 0 ? xff.substring(comma + 1) : xff).trim();
        }
        return req.getRemoteAddr();
    }

    /** idle 버킷 정리 — 메모리 무한증가 방지 (10분 미사용 제거, ban 중이면 유지). */
    @Scheduled(fixedDelay = 600_000L)
    void evictIdle() {
        long now = System.currentTimeMillis();
        buckets.entrySet().removeIf(e -> {
            Bucket b = e.getValue();
            return now - b.lastSeenMs > 600_000L && now >= b.bannedUntilMs;
        });
    }
}
