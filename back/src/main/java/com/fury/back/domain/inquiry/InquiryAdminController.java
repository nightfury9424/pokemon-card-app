package com.fury.back.domain.inquiry;

import com.fury.back.common.ApiResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.List;
import java.util.Map;

/**
 * 고객 문의 — 관리자 처리. /api/admin/** 아래라 AdminAllowlistFilter 자동 게이트(비-admin 403).
 */
@RestController
@RequestMapping("/api/admin/inquiries")
@RequiredArgsConstructor
public class InquiryAdminController {

    private final InquiryRepository inquiryRepository;

    /** 문의 목록 (status 필터 옵션) + 미처리(OPEN) 카운트. */
    @GetMapping
    public ApiResponse<Map<String, Object>> list(
            @RequestParam(required = false) String status) {
        List<Inquiry> rows = (status != null && !status.isBlank())
                ? inquiryRepository.findByStatusOrderByCreatedAtDesc(status)
                : inquiryRepository.findAllByOrderByCreatedAtDesc();
        return ApiResponse.ok(Map.of(
                "content", rows,
                "openCount", inquiryRepository.countByStatus("OPEN")));
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
        return ApiResponse.ok(inquiryRepository.save(inquiry));
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
