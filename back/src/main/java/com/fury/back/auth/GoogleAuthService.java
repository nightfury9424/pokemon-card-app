package com.fury.back.auth;

import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.Arrays;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class GoogleAuthService {

    private final UserRepository userRepository;
    private final JwtUtil jwtUtil;

    /**
     * 2026-05-29 multi-audience 지원 — iOS app + Web admin SPA 둘 다 ID token 발급 가능.
     * 쉼표 구분 list. 예: "iosClient.apps.googleusercontent.com,webClient.apps.googleusercontent.com".
     */
    @Value("${google.client-id}")
    private String googleClientIds;

    private Set<String> allowedAudiences;

    @PostConstruct
    public void initAudiences() {
        allowedAudiences = Arrays.stream(googleClientIds.split(","))
                .map(String::trim)
                .filter(s -> !s.isEmpty())
                .collect(Collectors.toUnmodifiableSet());
        if (allowedAudiences.isEmpty()) {
            throw new IllegalStateException(
                    "GOOGLE_CLIENT_ID env must contain at least one OAuth client ID (comma-separated for multi-audience).");
        }
    }

    private final RestClient restClient = RestClient.create();

    public LoginResult loginWithIdToken(String idToken) {
        Map<String, Object> payload = verifyIdToken(idToken);

        String googleId = (String) payload.get("sub");
        String email    = (String) payload.getOrDefault("email", "");

        // aud 검증 — allowedAudiences 중 하나와 매칭 (iOS / Web 둘 다 허용).
        String aud = (String) payload.get("aud");
        if (aud == null || !allowedAudiences.contains(aud)) {
            throw new IllegalArgumentException("Invalid Google client ID (aud=" + aud + ")");
        }

        User user = userRepository.findByGoogleId(googleId)
                .map(existing -> {
                    // 2026-06-08: 탈퇴(deletedAt) 계정 재로그인 차단 — 좀비 부활 방지(App Store 5.1.1 / PIPA).
                    // soft-delete row 는 3개월 보존(삭제 X), 차단만. (User.java:144 의도대로 구현)
                    if (existing.getDeletedAt() != null) {
                        // 403 — IllegalArgumentException(=200+notFound)은 앱이 성공 오인 위험이라 명시적 status.
                        throw new org.springframework.web.server.ResponseStatusException(
                                org.springframework.http.HttpStatus.FORBIDDEN,
                                "탈퇴한 계정입니다. 탈퇴 후에는 다시 로그인할 수 없어요.");
                    }
                    return syncEmailIfChanged(existing, email);
                })
                .orElseGet(() -> createUser(googleId, email));

        return new LoginResult(jwtUtil.generate(user.getUserId()), user.isOnboarded());
    }

    private Map<String, Object> verifyIdToken(String idToken) {
        return restClient.get()
                .uri("https://oauth2.googleapis.com/tokeninfo?id_token=" + idToken)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {});
    }

    private User createUser(String googleId, String email) {
        User user = User.builder()
                .userId("USR_" + UUID.randomUUID().toString().replace("-", "").substring(0, 20).toUpperCase())
                .googleId(googleId)
                .email(email)
                .onboarded(false)
                .build();
        return userRepository.save(user);
    }

    private User syncEmailIfChanged(User user, String email) {
        if (email == null || email.equals(user.getEmail())) return user;
        // 2026-06-08: builder 재조립 금지 — deletedAt/phoneVerified/appleId/suspension/scanConsent 등
        // 누락 필드가 NULL 로 덮이는 버그(탈퇴계정 부활·폰인증 소실). 로드된 엔티티 직접변경.
        user.updateEmail(email);
        return userRepository.save(user);
    }

    public LoginResult devLogin() {
        String devGoogleId = "DEV_TEST_USER";
        User user = userRepository.findByGoogleId(devGoogleId)
                .orElseGet(() -> userRepository.save(User.builder()
                        .userId("USR_DEV_TEST_USER_00000000000")
                        .googleId(devGoogleId)
                        .email("dev@test.com")
                        .onboarded(false)
                        .build()));
        return new LoginResult(jwtUtil.generate(user.getUserId()), user.isOnboarded());
    }

    public record LoginResult(String accessToken, boolean onboarded) {}
}
