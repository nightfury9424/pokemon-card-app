package com.fury.back.auth;

import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;

import java.util.Map;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class GoogleAuthService {

    private final UserRepository userRepository;
    private final JwtUtil jwtUtil;

    @Value("${google.client-id}")
    private String googleClientId;

    private final RestClient restClient = RestClient.create();

    public LoginResult loginWithIdToken(String idToken) {
        Map<String, Object> payload = verifyIdToken(idToken);

        String googleId = (String) payload.get("sub");
        String email    = (String) payload.getOrDefault("email", "");

        // aud 검증 (자기 Client ID인지 확인)
        String aud = (String) payload.get("aud");
        if (!googleClientId.equals(aud)) {
            throw new IllegalArgumentException("Invalid Google client ID");
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
