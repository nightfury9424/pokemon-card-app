package com.fury.back.domain.user;

import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

@Tag(name = "User", description = "사용자 정보 API")
@RestController
@RequestMapping("/api/users")
@RequiredArgsConstructor
public class UserController {

    private final UserRepository userRepository;

    @Operation(summary = "내 정보 조회")
    @GetMapping("/me")
    public ReturnData<Map<String, Object>> getMe(@AuthenticationPrincipal String userId) {
        return userRepository.findById(userId)
                .map(user -> ReturnData.success(Map.<String, Object>of(
                        "userId", user.getUserId(),
                        "nickname", user.getNickname(),
                        "profileImageUrl", user.getProfileImageUrl() != null ? user.getProfileImageUrl() : ""
                )))
                .orElse(ReturnData.success(Map.of("userId", userId, "nickname", "알 수 없음", "profileImageUrl", "")));
    }
}
