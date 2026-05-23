package com.fury.back.config;

import com.fury.back.auth.AdminAllowlistFilter;
import com.fury.back.auth.InternalTokenFilter;
import com.fury.back.auth.JwtAuthFilter;
import com.fury.back.auth.OnboardingGuardFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.annotation.web.configurers.AbstractHttpConfigurer;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import java.util.Arrays;
import java.util.List;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    /** Admin path patterns — SecurityConfig matcher + AdminAllowlistFilter 단일 진실원. */
    public static final String[] ADMIN_PATH_PATTERNS = {
            "/api/admin/**",
            "/api/prices/admin/**",
            "/api/price/admin/**"
    };

    private final JwtAuthFilter jwtAuthFilter;
    private final OnboardingGuardFilter onboardingGuardFilter;
    private final InternalTokenFilter internalTokenFilter;
    private final AdminAllowlistFilter adminAllowlistFilter;

    @Value("${app.cors.allowed-origins}")
    private String corsAllowedOrigins;

    @Value("${app.admin.auth-enabled:false}")
    private boolean adminAuthEnabled;

    @Value("${app.api.auth-enforced:false}")
    private boolean apiAuthEnforced;

    @Value("${app.auth.dev-login-enabled:true}")
    private boolean devLoginEnabled;

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        http
                .csrf(AbstractHttpConfigurer::disable)
                .cors(cors -> cors.configurationSource(corsConfigurationSource()))
                .sessionManagement(s -> s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
                .authorizeHttpRequests(auth -> {
                    // 0. /api/auth/dev/** — 개발용 로그인 endpoint (Codex Critical 4).
                    //    prod에선 누구나 JWT 발급 차단 (devLoginEnabled=false → denyAll).
                    if (devLoginEnabled) {
                        auth.requestMatchers("/api/auth/dev/**").permitAll();
                    } else {
                        auth.requestMatchers("/api/auth/dev/**").denyAll();
                    }

                    // 1. 항상 public
                    //    - /api/auth: 로그인 자체이므로 public 필수 (dev/** 제외 — 위에서 처리)
                    //    - /api/health: 헬스체크
                    //    - /images: Flutter Image.network가 JWT header 미부착 → Phase 2에서 별도 처리
                    //    - /ws: WebSocket — 핸드셰이크 JWT는 Phase 2
                    //    - swagger/api-docs: prod 닫을지 Phase 2
                    auth.requestMatchers(
                            "/api/auth/**",
                            "/api/health",
                            "/api/internal/**",   // InternalTokenFilter가 token 검증, nginx에서 외부 차단
                            "/images/**",
                            "/ws/**",
                            "/swagger-ui/**",
                            "/swagger-ui.html",
                            "/api-docs/**"
                    ).permitAll();

                    // 2. admin API — ADMIN_AUTH_ENABLED toggle.
                    //    local default permitAll (편의), prod=true → authenticated() + AdminAllowlistFilter.
                    //    추가 보호: AdminAllowlistFilter (D-7 임시 게이트) — JwtAuthFilter 다음에서 userId
                    //    가 app.admin.user-ids 에 없으면 403. 출시 후 ROLE_ADMIN 정식 전환.
                    if (adminAuthEnabled) {
                        auth.requestMatchers(ADMIN_PATH_PATTERNS).authenticated();
                    } else {
                        auth.requestMatchers(ADMIN_PATH_PATTERNS).permitAll();
                    }

                    // 3. 사용자/거래 API — API_AUTH_ENFORCED toggle.
                    //    local default permitAll (개발 편의), prod=true → authenticated().
                    //    정책: 로그인하지 않으면 카드/시세 화면 자체를 못 쓰는 구조 → prod에서 인증 강제.
                    String[] userPaths = {
                            "/api/cards/**",
                            "/api/prices/**",
                            "/api/products/**",
                            "/api/assets/**",
                            "/api/trades",
                            "/api/trades/**",
                            "/api/buy-orders/**",
                            "/api/notifications/**",
                            "/api/card-interests/**",
                            "/api/reports/**",
                            "/api/scanner/**",
                            "/api/grading/**",
                            "/api/images/secure/**"   // Phase 1-7: 사용자 업로드 이미지 proxy (S3/local stream)
                    };
                    if (apiAuthEnforced) {
                        auth.requestMatchers(userPaths).authenticated();
                    } else {
                        auth.requestMatchers(userPaths).permitAll();
                    }

                    // 4. 나머지 인증
                    auth.anyRequest().authenticated();
                })
                .addFilterBefore(jwtAuthFilter, UsernamePasswordAuthenticationFilter.class)
                .addFilterBefore(internalTokenFilter, JwtAuthFilter.class)
                .addFilterAfter(adminAllowlistFilter, JwtAuthFilter.class)
                .addFilterAfter(onboardingGuardFilter, AdminAllowlistFilter.class);

        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();

        // Phase 1-3: env 주입 comma-separated allow-list.
        // wildcard "*" + allowCredentials(true)는 spec invalid라 정확한 origin 권고.
        // prod는 CORS_ALLOWED_ORIGINS 명시 주입 필수.
        List<String> origins = Arrays.stream(corsAllowedOrigins.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .toList();
        config.setAllowedOrigins(origins);
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
