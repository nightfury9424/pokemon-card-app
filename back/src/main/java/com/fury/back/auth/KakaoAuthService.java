package com.fury.back.auth;

import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;

import java.util.Map;
import java.util.UUID;

@Service
@RequiredArgsConstructor
public class KakaoAuthService {

    private final UserRepository userRepository;
    private final JwtUtil jwtUtil;

    @Value("${kakao.rest-api-key}")
    private String restApiKey;

    @Value("${kakao.client-secret}")
    private String clientSecret;

    @Value("${kakao.redirect-uri}")
    private String redirectUri;

    private final RestClient restClient = RestClient.create();

    // 인가코드 → 카카오 액세스 토큰
    public String getKakaoAccessToken(String code) {
        MultiValueMap<String, String> params = new LinkedMultiValueMap<>();
        params.add("grant_type", "authorization_code");
        params.add("client_id", restApiKey);
        params.add("redirect_uri", redirectUri);
        params.add("code", code);
        params.add("client_secret", clientSecret);

        Map<String, Object> response = restClient.post()
                .uri("https://kauth.kakao.com/oauth/token")
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .body(params)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {});

        return (String) response.get("access_token");
    }

    // 카카오 액세스 토큰 → 우리 JWT (Flutter용)
    public String loginWithKakaoToken(String kakaoAccessToken) {
        Map<String, Object> userInfo = getKakaoUserInfo(kakaoAccessToken);
        return processLogin(userInfo);
    }

    // 인가코드 → 우리 JWT (웹 콜백용)
    public String loginWithCode(String code) {
        String kakaoAccessToken = getKakaoAccessToken(code);
        Map<String, Object> userInfo = getKakaoUserInfo(kakaoAccessToken);
        return processLogin(userInfo);
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> getKakaoUserInfo(String kakaoAccessToken) {
        return restClient.get()
                .uri("https://kapi.kakao.com/v2/user/me")
                .header("Authorization", "Bearer " + kakaoAccessToken)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {});
    }

    @SuppressWarnings("unchecked")
    private String processLogin(Map<String, Object> userInfo) {
        String kakaoId = String.valueOf(userInfo.get("id"));

        Map<String, Object> kakaoAccount = (Map<String, Object>) userInfo.get("kakao_account");
        Map<String, Object> profile = (Map<String, Object>) kakaoAccount.get("profile");

        String nickname = (String) profile.getOrDefault("nickname", "포켓몬 트레이너");
        String profileImageUrl = (String) profile.get("profile_image_url");

        User user = userRepository.findByKakaoId(kakaoId)
                .map(existing -> updateUser(existing, nickname, profileImageUrl))
                .orElseGet(() -> createUser(kakaoId, nickname, profileImageUrl));

        return jwtUtil.generate(user.getUserId());
    }

    private User createUser(String kakaoId, String nickname, String profileImageUrl) {
        User user = User.builder()
                .userId("USR_" + UUID.randomUUID().toString().replace("-", "").substring(0, 20).toUpperCase())
                .kakaoId(kakaoId)
                .nickname(nickname)
                .profileImageUrl(profileImageUrl)
                .build();
        return userRepository.save(user);
    }

    // 개발용 테스트 로그인 (에뮬레이터 테스트 전용)
    public String devLogin() {
        String devKakaoId = "DEV_TEST_USER";
        User user = userRepository.findByKakaoId(devKakaoId)
                .orElseGet(() -> userRepository.save(User.builder()
                        .userId("USR_DEV_TEST_USER_00000000000")
                        .kakaoId(devKakaoId)
                        .nickname("개발자")
                        .profileImageUrl(null)
                        .build()));
        return jwtUtil.generate(user.getUserId());
    }

    private User updateUser(User user, String nickname, String profileImageUrl) {
        // 닉네임/프로필이 변경됐으면 업데이트
        if (!user.getNickname().equals(nickname) ||
                (profileImageUrl != null && !profileImageUrl.equals(user.getProfileImageUrl()))) {
            return userRepository.save(User.builder()
                    .userId(user.getUserId())
                    .kakaoId(user.getKakaoId())
                    .nickname(nickname)
                    .profileImageUrl(profileImageUrl)
                    .build());
        }
        return user;
    }
}
