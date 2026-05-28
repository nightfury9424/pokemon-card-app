package com.fury.back.domain.user;

import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.time.Duration;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

@Tag(name = "User", description = "사용자 정보 API")
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private static final int NICKNAME_COOLDOWN_DAYS = 30;

    private final UserRepository userRepository;
    private final NicknameValidator nicknameValidator;
    private final UserService userService;

    @Operation(summary = "계정 탈퇴 (App Review 5.1.1)",
            description = "현재 로그인한 사용자만 자기 계정 삭제 가능 — userId는 JWT subject에서만 추출, " +
                    "request param/body로 받지 않음. PII(nickname/email/profileImageUrl) 마스킹 + " +
                    "deletedAt 설정 + OPEN 매수/매도 자동 취소. 거래/채팅/신고/차단 기록은 보존 (분쟁·운영 증거).")
    @DeleteMapping("/me")
    public ReturnData<Map<String, Object>> deleteMyAccount(@AuthenticationPrincipal String userId) {
        return userService.deleteAccount(userId);
    }

    @Operation(summary = "내 정보 조회")
    @GetMapping("/me")
    public ReturnData<Map<String, Object>> getMe(@AuthenticationPrincipal String userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "사용자 없음"));
        Map<String, Object> data = new HashMap<>();
        data.put("userId", user.getUserId());
        data.put("nickname", user.getNickname() != null ? user.getNickname() : "");
        data.put("email", user.getEmail() != null ? user.getEmail() : "");
        data.put("profileImageUrl", user.getProfileImageUrl() != null ? user.getProfileImageUrl() : "");
        data.put("onboarded", user.isOnboarded());
        data.put("nicknameCooldownDaysLeft", nicknameCooldownDaysLeft(user.getNicknameChangedAt()));
        return ReturnData.success(data);
    }

    @Operation(summary = "닉네임 사용 가능 여부 확인 (안내용, 최종 방어는 저장 시 409)")
    @GetMapping("/nickname/check")
    public ReturnData<Map<String, Object>> checkNickname(@RequestParam("value") String value) {
        String normalized = nicknameValidator.normalize(value);
        nicknameValidator.validate(normalized);
        boolean taken = userRepository.existsByNicknameIgnoreCase(normalized);
        return ReturnData.success(Map.of("available", !taken));
    }

    @Operation(summary = "온보딩 완료 (닉네임 + 선택적 프로필 이미지)")
    @PutMapping("/onboarding")
    public ReturnData<Map<String, Object>> completeOnboarding(
            @AuthenticationPrincipal String userId,
            @RequestBody Map<String, String> body
    ) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "사용자 없음"));
        if (user.isOnboarded()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "이미 온보딩이 완료되었습니다");
        }
        String normalized = nicknameValidator.normalize(body.get("nickname"));
        nicknameValidator.validate(normalized);

        String profileImageUrl = body.get("profileImageUrl");
        User updated = User.builder()
                .userId(user.getUserId())
                .googleId(user.getGoogleId())
                .nickname(normalized)
                .email(user.getEmail())
                .profileImageUrl(profileImageUrl != null && !profileImageUrl.isBlank() ? profileImageUrl : null)
                .onboarded(true)
                .nicknameChangedAt(LocalDateTime.now())
                .build();
        return ReturnData.success(saveOrConflict(updated));
    }

    @Operation(summary = "닉네임 변경 (30일 cooldown)")
    @PutMapping("/nickname")
    public ReturnData<Map<String, Object>> changeNickname(
            @AuthenticationPrincipal String userId,
            @RequestBody Map<String, String> body
    ) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "사용자 없음"));
        if (!user.isOnboarded()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "온보딩이 필요합니다");
        }
        LocalDateTime cooldownEnd = cooldownEnd(user.getNicknameChangedAt());
        if (cooldownEnd != null && LocalDateTime.now().isBefore(cooldownEnd)) {
            long daysLeft = nicknameCooldownDaysLeft(user.getNicknameChangedAt());
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                    "닉네임 변경은 " + daysLeft + "일 후 가능합니다");
        }
        String normalized = nicknameValidator.normalize(body.get("nickname"));
        nicknameValidator.validate(normalized);
        if (normalized.equalsIgnoreCase(user.getNickname())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "현재 닉네임과 동일합니다");
        }

        User updated = User.builder()
                .userId(user.getUserId())
                .googleId(user.getGoogleId())
                .nickname(normalized)
                .email(user.getEmail())
                .profileImageUrl(user.getProfileImageUrl())
                .onboarded(true)
                .nicknameChangedAt(LocalDateTime.now())
                .build();
        return ReturnData.success(saveOrConflict(updated));
    }

    private Map<String, Object> saveOrConflict(User user) {
        try {
            User saved = userRepository.save(user);
            return Map.of(
                    "userId", saved.getUserId(),
                    "nickname", saved.getNickname(),
                    "profileImageUrl", saved.getProfileImageUrl() != null ? saved.getProfileImageUrl() : "",
                    "onboarded", saved.isOnboarded(),
                    "nicknameCooldownDaysLeft", nicknameCooldownDaysLeft(saved.getNicknameChangedAt())
            );
        } catch (DataIntegrityViolationException e) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "이미 사용 중인 닉네임입니다");
        }
    }

    private LocalDateTime cooldownEnd(LocalDateTime changedAt) {
        return changedAt == null ? null : changedAt.plusDays(NICKNAME_COOLDOWN_DAYS);
    }

    /**
     * 현재 시각 기준 남은 cooldown 일수 — ceil로 계산해서 1ms라도 남으면 1일로 표시.
     * 만료 시 0 반환. 차단 판단(isBefore)과는 별개로 UX 표시용.
     */
    private long nicknameCooldownDaysLeft(LocalDateTime changedAt) {
        LocalDateTime end = cooldownEnd(changedAt);
        if (end == null) return 0;
        Duration remaining = Duration.between(LocalDateTime.now(), end);
        if (remaining.isZero() || remaining.isNegative()) return 0;
        long millis = remaining.toMillis();
        long oneDayMillis = 86_400_000L;
        return (millis + oneDayMillis - 1) / oneDayMillis;
    }
}
