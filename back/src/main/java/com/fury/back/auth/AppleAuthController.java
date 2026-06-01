package com.fury.back.auth;

import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Tag(name = "Auth", description = "Apple 로그인 / JWT 발급")
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AppleAuthController {

    private final AppleAuthService appleAuthService;

    @Operation(summary = "Apple identity 토큰으로 JWT 발급 (Sign in with Apple)",
            description = "iOS sign_in_with_apple 에서 받은 identityToken 을 전달하면 서비스 JWT 를 발급합니다.")
    @PostMapping("/apple/token")
    public ReturnData<Map<String, Object>> loginWithAppleToken(@RequestBody Map<String, String> body) {
        String identityToken = body.get("identityToken");
        if (identityToken == null || identityToken.isBlank()) {
            identityToken = body.get("idToken"); // 호환
        }
        if (identityToken == null || identityToken.isBlank()) {
            return ReturnData.badRequest("identityToken 이 필요합니다.");
        }
        try {
            GoogleAuthService.LoginResult result = appleAuthService.loginWithIdToken(identityToken);
            return ReturnData.success(Map.of(
                    "accessToken", result.accessToken(),
                    "requiresOnboarding", !result.onboarded()
            ));
        } catch (Exception e) {
            return ReturnData.fail("F401", "Apple 로그인 검증 실패: " + e.getMessage());
        }
    }
}
