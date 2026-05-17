package com.fury.back.auth;

import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Tag(name = "Auth", description = "Google 로그인 / JWT 발급")
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class GoogleAuthController {

    private final GoogleAuthService googleAuthService;

    @Operation(summary = "Google ID 토큰으로 JWT 발급 (Flutter 앱용)",
            description = "Flutter google_sign_in SDK에서 받은 ID 토큰을 전달하면 서비스 JWT를 발급합니다.")
    @PostMapping("/google/token")
    public ReturnData<Map<String, Object>> loginWithGoogleToken(@RequestBody Map<String, String> body) {
        String idToken = body.get("idToken");
        if (idToken == null || idToken.isBlank()) {
            return ReturnData.badRequest("idToken이 필요합니다.");
        }
        GoogleAuthService.LoginResult result = googleAuthService.loginWithIdToken(idToken);
        return ReturnData.success(Map.of(
                "accessToken", result.accessToken(),
                "requiresOnboarding", !result.onboarded()
        ));
    }

    @Operation(summary = "개발용 테스트 로그인")
    @PostMapping("/dev/login")
    public ReturnData<Map<String, Object>> devLogin() {
        GoogleAuthService.LoginResult result = googleAuthService.devLogin();
        return ReturnData.success(Map.of(
                "accessToken", result.accessToken(),
                "requiresOnboarding", !result.onboarded()
        ));
    }
}
