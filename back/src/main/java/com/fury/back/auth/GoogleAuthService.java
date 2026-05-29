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
                .map(existing -> syncEmailIfChanged(existing, email))
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
        return userRepository.save(User.builder()
                .userId(user.getUserId())
                .googleId(user.getGoogleId())
                .nickname(user.getNickname())
                .email(email)
                .profileImageUrl(user.getProfileImageUrl())
                .onboarded(user.isOnboarded())
                .nicknameChangedAt(user.getNicknameChangedAt())
                .build());
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
