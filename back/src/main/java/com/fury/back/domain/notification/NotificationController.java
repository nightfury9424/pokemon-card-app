package com.fury.back.domain.notification;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@Tag(name = "Notification", description = "알림")
@RestController
@RequestMapping("/api/notifications")
@RequiredArgsConstructor
public class NotificationController {

    private final NotificationService notificationService;
    private final JwtUtil jwtUtil;

    @Operation(summary = "내 알림 list (최근 50개)")
    @GetMapping("/me")
    public ReturnData<List<Map<String, Object>>> getMine(HttpServletRequest request) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.success(List.of());
        return ReturnData.success(notificationService.getRecent(userId).stream()
                .map(this::toMap)
                .toList());
    }

    @Operation(summary = "내 알림 unread count")
    @GetMapping("/me/unread-count")
    public ReturnData<Map<String, Long>> getUnreadCount(HttpServletRequest request) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.success(Map.of("count", 0L));
        return ReturnData.success(Map.of("count", notificationService.getUnreadCount(userId)));
    }

    @Operation(summary = "알림 단건 읽음 처리")
    @PostMapping("/{notificationId}/read")
    public ReturnData<Void> markRead(
            HttpServletRequest request,
            @PathVariable String notificationId) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.fail("F403", "인증 필요");
        notificationService.markRead(notificationId, userId);
        return ReturnData.success();
    }

    @Operation(summary = "모든 알림 읽음 처리")
    @PostMapping("/me/read-all")
    public ReturnData<Void> markAllRead(HttpServletRequest request) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.fail("F403", "인증 필요");
        notificationService.markAllRead(userId);
        return ReturnData.success();
    }

    private Map<String, Object> toMap(Notification n) {
        return Map.of(
                "notificationId", n.getNotificationId(),
                "type", n.getType(),
                "title", n.getTitle(),
                "body", n.getBody() != null ? n.getBody() : "",
                "linkCardId", n.getLinkCardId() != null ? n.getLinkCardId() : "",
                "isRead", n.getIsRead(),
                "createdAt", n.getCreatedAt().toString()
        );
    }

    private String extractUserId(HttpServletRequest request) {
        String bearer = request.getHeader("Authorization");
        if (StringUtils.hasText(bearer) && bearer.startsWith("Bearer ")) {
            String token = bearer.substring(7);
            if (jwtUtil.isValid(token)) return jwtUtil.extractUserId(token);
        }
        return null;
    }
}
