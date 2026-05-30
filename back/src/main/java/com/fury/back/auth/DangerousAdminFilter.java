package com.fury.back.auth;

import java.io.IOException;
import java.util.Set;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * 가격/매핑 시스템에 직접 영향 가는 위험 admin endpoint 가드.
 *
 * <p>대상 endpoint — 2026-05-30 사고 (refresh-ko-estimates 수동 호출 → v6_apply 보정 우회 →
 * chase 카드 시세 망가짐) 재발 방지:
 * <ul>
 *   <li>POST /api/internal/admin/refresh-ko-estimates</li>
 *   <li>POST /api/internal/admin/backfill-ko-history</li>
 *   <li>POST /api/prices/admin/refresh-ko-estimates</li>
 *   <li>POST /api/prices/admin/backfill-ko-history</li>
 *   <li>POST /api/prices/admin/refresh-ko-live</li>
 *   <li>POST /api/prices/admin/market-adjustment</li>
 *   <li>POST /api/prices/admin/clear-card-mappings</li>
 *   <li>POST /api/prices/admin/recalculate-en-jp-ratios</li>
 * </ul>
 *
 * <p>동작:
 * <ul>
 *   <li>app.admin.dangerous-price-actions.enabled=false (기본) → 403</li>
 *   <li>=true → 통과 (운영 cron / 정상 admin 시점에 env 로 enable)</li>
 *   <li>POST 외 메서드는 가드 대상 X (GET /admin/market-adjustment 같은 read-only 보존)</li>
 * </ul>
 *
 * <p>운영 정상 흐름:
 * <ul>
 *   <li>매일 23:45 Spring @Scheduled `refreshKoEstimates()` 가 자동 호출 → admin 수동 X 필요</li>
 *   <li>23:52 cron `v6_apply_daily.sh` 가 chase 보정 overlay</li>
 *   <li>23:50/55 hold/sanity cron 보정</li>
 * </ul>
 */
@Component
public class DangerousAdminFilter extends OncePerRequestFilter {

    private static final Set<String> GUARDED_POST_PATHS = Set.of(
            "/api/internal/admin/refresh-ko-estimates",
            "/api/internal/admin/backfill-ko-history",
            "/api/prices/admin/refresh-ko-estimates",
            "/api/prices/admin/backfill-ko-history",
            "/api/prices/admin/refresh-ko-live",
            "/api/prices/admin/market-adjustment",
            "/api/prices/admin/clear-card-mappings",
            "/api/prices/admin/recalculate-en-jp-ratios"
    );

    private final boolean dangerousEnabled;

    public DangerousAdminFilter(
            @Value("${app.admin.dangerous-price-actions.enabled:false}") boolean dangerousEnabled) {
        this.dangerousEnabled = dangerousEnabled;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        // 가드 비활성 (env enable) — pass-through.
        if (dangerousEnabled) {
            filterChain.doFilter(request, response);
            return;
        }
        // POST 만 가드 (GET read-only 보존).
        if (!"POST".equalsIgnoreCase(request.getMethod())) {
            filterChain.doFilter(request, response);
            return;
        }
        String path = request.getRequestURI();
        if (path != null && GUARDED_POST_PATHS.contains(path)) {
            response.setStatus(HttpServletResponse.SC_FORBIDDEN);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write(
                "{\"error\":\"DANGEROUS_PRICE_ACTION_DISABLED\","
              + "\"message\":\"가격 시세에 직접 영향 가는 endpoint. 운영 cron 외 호출 차단됨. "
              + "임시 활성: env DANGEROUS_PRICE_ACTIONS_ENABLED=true 후 재시작.\","
              + "\"reason\":\"2026-05-30 refresh-ko-estimates 수동 호출 → v6_apply 보정 우회 → chase 시세 망가짐 사고 재발 방지.\"}");
            return;
        }
        filterChain.doFilter(request, response);
    }
}
