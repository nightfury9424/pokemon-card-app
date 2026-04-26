package com.fury.back.auth;

import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Tag(name = "Auth", description = "카카오 로그인 / JWT 발급")
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class KakaoAuthController {

    private final KakaoAuthService kakaoAuthService;

    @Value("${kakao.rest-api-key}")
    private String restApiKey;

    @Value("${kakao.redirect-uri}")
    private String redirectUri;

    @Operation(summary = "카카오 로그인 페이지로 이동 (브라우저 테스트용)")
    @GetMapping("/kakao")
    public void redirectToKakao(jakarta.servlet.http.HttpServletResponse response) throws Exception {
        String url = "https://kauth.kakao.com/oauth/authorize"
                + "?client_id=" + restApiKey
                + "&redirect_uri=" + redirectUri
                + "&response_type=code";
        response.sendRedirect(url);
    }

    @Operation(summary = "카카오 OAuth 콜백 (인가코드 → JWT)")
    @GetMapping("/kakao/callback")
    public ReturnData<Map<String, String>> kakaoCallback(@RequestParam String code) {
        String jwt = kakaoAuthService.loginWithCode(code);
        return ReturnData.success(Map.of("accessToken", jwt));
    }

    @Operation(summary = "카카오 액세스 토큰으로 JWT 발급 (Flutter 앱용)",
            description = "Flutter 카카오 SDK에서 받은 액세스 토큰을 전달하면 우리 서비스 JWT를 발급합니다.")
    @PostMapping("/kakao/token")
    public ReturnData<Map<String, String>> loginWithToken(@RequestBody Map<String, String> body) {
        String kakaoAccessToken = body.get("kakaoAccessToken");
        String jwt = kakaoAuthService.loginWithKakaoToken(kakaoAccessToken);
        return ReturnData.success(Map.of("accessToken", jwt));
    }

    @Operation(summary = "개발용 테스트 로그인 (에뮬레이터 테스트 전용)")
    @PostMapping("/dev/login")
    public ReturnData<Map<String, String>> devLogin() {
        String jwt = kakaoAuthService.devLogin();
        return ReturnData.success(Map.of("accessToken", jwt));
    }
}
