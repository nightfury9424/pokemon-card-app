package com.fury.back.domain.inquiry;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 정지(suspended) 계정 전용 이의신청.
 *
 * <p>정지자는 {@code DeletedUserGuardFilter} 로 모든 API 가 403 {@code USER_SUSPENDED} 인데,
 * 이 POST 하나만 allowlist 로 열어 앱 내 이의신청을 가능하게 한다.
 * (전체 {@code /api/inquiries} 는 열지 않음 — 목록/상세/일반문의는 정지자에게 계속 403.)
 *
 * <p>보안: userId 는 클라 파라미터를 신뢰하지 않고 JWT principal 로만 세팅.
 * 중복: 미처리(OPEN) 이의신청이 이미 있으면 재접수 차단.
 */
@Tag(name = "SuspensionAppeal", description = "정지 이의신청")
@RestController
@RequestMapping("/api/suspension-appeals")
@RequiredArgsConstructor
public class SuspensionAppealController {

    private static final String CATEGORY = "SUSPENSION_APPEAL";

    private final InquiryRepository inquiryRepository;

    @Operation(summary = "정지 이의신청 등록", description = "정지 계정 전용. 사유 검토 요청을 문의로 저장.")
    @PostMapping
    public ReturnData<Map<String, String>> create(
            @AuthenticationPrincipal String userId,
            @RequestBody Map<String, Object> body) {
        if (userId == null || userId.isBlank()) return ReturnData.fail("F403", "인증이 필요합니다.");

        final Map<String, Object> data = (body.get("data") instanceof Map<?, ?> nested)
                ? castMap(nested) : body;

        String content = data.get("content") != null ? String.valueOf(data.get("content")).trim() : "";
        if (content.isBlank()) return ReturnData.badRequest("이의신청 내용을 입력해 주세요.");
        if (content.length() > 5000) content = content.substring(0, 5000);
        String contactEmail = data.get("contactEmail") != null
                ? String.valueOf(data.get("contactEmail")) : null;

        // 중복 방지 — 미처리(OPEN) 이의신청이 이미 있으면 재접수 차단.
        if (inquiryRepository.existsByUserIdAndCategoryAndStatus(userId, CATEGORY, "OPEN")) {
            return ReturnData.fail("F409", "이미 접수된 이의신청이 검토 중입니다.");
        }

        Inquiry inquiry = Inquiry.builder()
                .inquiryId(IdGenerator.generate())
                .userId(userId)
                .category(CATEGORY)
                .title("정지 이의신청")
                .content(content)
                .contactEmail(contactEmail)
                .status("OPEN")
                .build();
        Inquiry saved = inquiryRepository.save(inquiry);
        return ReturnData.success(Map.of("inquiryId", saved.getInquiryId()));
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMap(Map<?, ?> m) {
        return (Map<String, Object>) m;
    }
}
