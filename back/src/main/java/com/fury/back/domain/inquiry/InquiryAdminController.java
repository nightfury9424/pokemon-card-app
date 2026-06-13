package com.fury.back.domain.inquiry;

import com.fury.back.common.ApiResponse;
import com.fury.back.domain.notification.NotificationService;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * 고객 문의 — 관리자 처리. /api/admin/** 아래라 AdminAllowlistFilter 자동 게이트(비-admin 403).
 */
@Slf4j
@RestController
@RequestMapping("/api/admin/inquiries")
@RequiredArgsConstructor
public class InquiryAdminController {

    private final InquiryRepository inquiryRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    /**
     * 문의 목록 — 작성자 닉네임/정지상태 resolve + 분류 필터.
     * <p>{@code category} 지정 시 그 분류만(예: 정지 이의신청 페이지 = SUSPENSION_APPEAL),
     * {@code excludeCategory} 지정 시 그 분류 제외(고객 문의 페이지 = SUSPENSION_APPEAL 제외).
     * openCount 는 필터된 목록 기준이라 페이지별로 정확.
     */
    @GetMapping
    public ApiResponse<Map<String, Object>> list(
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String category,
            @RequestParam(required = false) String excludeCategory) {
        List<Inquiry> base = (status != null && !status.isBlank())
                ? inquiryRepository.findByStatusOrderByCreatedAtDesc(status)
                : inquiryRepository.findAllByOrderByCreatedAtDesc();

        List<Inquiry> rows = base.stream()
                .filter(i -> category == null || category.isBlank() || category.equals(i.getCategory()))
                .filter(i -> excludeCategory == null || excludeCategory.isBlank()
                        || !excludeCategory.equals(i.getCategory()))
                .toList();

        // userId → User 배치 조회 (닉네임 + 정지상태/사유 — 이의신청 페이지에서 활용).
        Set<String> userIds = rows.stream()
                .map(Inquiry::getUserId).filter(Objects::nonNull).collect(Collectors.toSet());
        Map<String, User> users = userRepository.findAllById(userIds).stream()
                .collect(Collectors.toMap(User::getUserId, u -> u));

        List<Map<String, Object>> content = new ArrayList<>();
        for (Inquiry i : rows) {
            User u = users.get(i.getUserId());
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("inquiryId", i.getInquiryId());
            m.put("userId", i.getUserId());
            m.put("nickname", u != null ? u.getNickname() : null);
            m.put("suspended", u != null && u.isSuspended());
            m.put("suspensionReason", u != null ? u.getSuspensionReason() : null);
            m.put("category", i.getCategory());
            m.put("title", i.getTitle());
            m.put("content", i.getContent());
            m.put("imageUrls", com.fury.back.storage.StorageKeyUrls.toProxyCsv(i.getImageKeys())); // 첨부 사진 프록시 URL CSV
            m.put("contactEmail", i.getContactEmail());
            m.put("status", i.getStatus());
            m.put("createdAt", i.getCreatedAt());
            m.put("adminReply", i.getAdminReply());
            m.put("repliedBy", i.getRepliedBy());
            m.put("repliedAt", i.getRepliedAt());
            content.add(m);
        }

        long openCount = rows.stream().filter(i -> "OPEN".equals(i.getStatus())).count();
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("content", content);
        result.put("openCount", openCount);
        return ApiResponse.ok(result);
    }

    /** 관리자 답변 등록 → ANSWERED. */
    @PatchMapping("/{inquiryId}/reply")
    public ApiResponse<Inquiry> reply(
            @PathVariable String inquiryId,
            @AuthenticationPrincipal String adminUserId,
            @RequestBody Map<String, String> body) {
        Inquiry inquiry = inquiryRepository.findById(inquiryId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "INQUIRY_NOT_FOUND"));
        String reply = body.getOrDefault("reply", "").trim();
        if (reply.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "REPLY_REQUIRED");
        }
        inquiry.markAnswered(reply, adminUserId);
        Inquiry saved = inquiryRepository.save(inquiry);  // 답변 먼저 커밋
        // 답변 등록 알림(인앱+FCM). ★알림 실패해도 답변 등록은 절대 영향 없게 try-catch 격리(틱 교훈).
        try {
            notificationService.notifyInquiryAnswered(inquiry.getUserId(), inquiry.getTitle(), reply);
        } catch (Exception e) {
            log.warn("[Inquiry] 답변 알림 실패(답변은 저장됨) inquiryId={}: {}", inquiryId, e.getMessage());
        }
        return ApiResponse.ok(saved);
    }

    /** 종료 처리 (답변 없이 닫기 등). */
    @PatchMapping("/{inquiryId}/close")
    public ApiResponse<Inquiry> close(@PathVariable String inquiryId) {
        Inquiry inquiry = inquiryRepository.findById(inquiryId)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "INQUIRY_NOT_FOUND"));
        inquiry.markClosed();
        return ApiResponse.ok(inquiryRepository.save(inquiry));
    }
}
