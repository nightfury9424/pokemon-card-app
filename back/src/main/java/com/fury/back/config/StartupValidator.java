package com.fury.back.config;

import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;

import java.util.Arrays;
import java.util.Set;

/**
 * Phase 1-2: prod profile에서 필수 secret/설정 누락 시 시작 실패.
 *
 * 검증 대상 (prod/staging only):
 *   - JWT_SECRET: dev placeholder/<32 bytes → fail
 *   - DB_PASSWORD: 빈값 → fail
 *   - ADMIN_AUTH_ENABLED: prod에서 false → fail (Codex High 6)
 *   - API_AUTH_ENFORCED: prod에서 false → fail
 *   - DEV_LOGIN_ENABLED: prod에서 true → fail (Codex Critical 4)
 *
 * Profile 판별: Environment.getActiveProfiles() — SPRING_PROFILES_ACTIVE=prod,docker comma-list 정확 대응 (Codex High 5).
 * local/dev profile에서는 검증 skip.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class StartupValidator {

    private static final String DEV_JWT_PLACEHOLDER =
            "dev-secret-replace-in-prod-min-32-bytes-required-here";
    private static final int JWT_MIN_BYTES = 32;
    private static final Set<String> PROD_LIKE_PROFILES = Set.of("prod", "staging");

    private final Environment environment;

    @Value("${jwt.secret:}")
    private String jwtSecret;

    @Value("${spring.datasource.password:}")
    private String dbPassword;

    @Value("${app.admin.auth-enabled:false}")
    private boolean adminAuthEnabled;

    @Value("${app.api.auth-enforced:false}")
    private boolean apiAuthEnforced;

    @Value("${app.auth.dev-login-enabled:true}")
    private boolean devLoginEnabled;

    @PostConstruct
    public void validate() {
        String[] activeProfiles = environment.getActiveProfiles();
        boolean isProd = Arrays.stream(activeProfiles)
                .anyMatch(p -> PROD_LIKE_PROFILES.contains(p.toLowerCase()));

        if (!isProd) {
            log.info("[StartupValidator] profiles={} — fail-fast skipped (local/dev).",
                    Arrays.toString(activeProfiles));
            return;
        }

        StringBuilder errors = new StringBuilder();

        if (jwtSecret == null || jwtSecret.isBlank()) {
            errors.append("  - JWT_SECRET must be set (env or property).\n");
        } else if (DEV_JWT_PLACEHOLDER.equals(jwtSecret)) {
            errors.append("  - JWT_SECRET still uses dev placeholder. Set a production secret.\n");
        } else if (jwtSecret.getBytes().length < JWT_MIN_BYTES) {
            errors.append("  - JWT_SECRET must be at least ").append(JWT_MIN_BYTES)
                    .append(" bytes (current: ").append(jwtSecret.getBytes().length).append(" bytes).\n");
        }

        if (dbPassword == null || dbPassword.isBlank()) {
            errors.append("  - DB_PASSWORD must be set in prod-like profile.\n");
        }

        // Codex High 6: auth toggle prod 강제
        if (!adminAuthEnabled) {
            errors.append("  - ADMIN_AUTH_ENABLED=true must be set in prod-like profile (admin API protection).\n");
        }
        if (!apiAuthEnforced) {
            errors.append("  - API_AUTH_ENFORCED=true must be set in prod-like profile (user API protection).\n");
        }

        // Codex Critical 4: dev-login prod 차단 강제
        if (devLoginEnabled) {
            errors.append("  - DEV_LOGIN_ENABLED=false must be set in prod-like profile (/api/auth/dev/** must be denied).\n");
        }

        if (!errors.isEmpty()) {
            String msg = "Production startup validation failed (profiles=" + Arrays.toString(activeProfiles) + "):\n"
                    + errors
                    + "Required env vars: JWT_SECRET, DB_PASSWORD, ADMIN_AUTH_ENABLED=true, "
                    + "API_AUTH_ENFORCED=true, DEV_LOGIN_ENABLED=false.";
            log.error("[StartupValidator] {}", msg);
            throw new IllegalStateException(msg);
        }

        log.info("[StartupValidator] profiles={} — secrets + auth toggles validated.",
                Arrays.toString(activeProfiles));
    }
}
