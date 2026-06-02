package com.fury.back.domain.notification;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Tag(name = "Notification", description = "FCM 기기 푸시 토큰 등록")
@RestController
@RequestMapping("/api/notifications")
@RequiredArgsConstructor
public class FcmTokenController {

    private final FcmTokenRepository fcmTokenRepository;

    @Operation(summary = "FCM 토큰 등록/갱신", description = "앱이 firebase_messaging 토큰을 받으면 호출. token unique upsert.")
    @PostMapping("/fcm-token")
    @Transactional
    public ReturnData<Map<String, Object>> register(
            @AuthenticationPrincipal String userId,
            @RequestBody Map<String, String> body) {
        String token = body.get("token");
        if (token == null || token.isBlank()) {
            return ReturnData.badRequest("token 이 필요합니다.");
        }
        String platform = body.getOrDefault("platform", "ios");
        fcmTokenRepository.findByToken(token).ifPresentOrElse(
                existing -> existing.relink(userId, platform),
                () -> fcmTokenRepository.save(FcmToken.builder()
                        .tokenId(IdGenerator.generate())
                        .userId(userId)
                        .token(token)
                        .platform(platform)
                        .build()));
        return ReturnData.success(Map.of("ok", true));
    }

    @Operation(summary = "FCM 토큰 해제", description = "로그아웃 시 호출 — 해당 기기 토큰 제거.")
    @DeleteMapping("/fcm-token")
    @Transactional
    public ReturnData<Map<String, Object>> unregister(
            @AuthenticationPrincipal String userId,
            @RequestParam String token) {
        // IDOR fix: 토큰 소유자 본인일 때만 삭제 (타인 토큰 값으로 푸시 차단 방지).
        fcmTokenRepository.findByToken(token)
                .filter(t -> userId != null && userId.equals(t.getUserId()))
                .ifPresent(fcmTokenRepository::delete);
        return ReturnData.success(Map.of("ok", true));
    }
}
