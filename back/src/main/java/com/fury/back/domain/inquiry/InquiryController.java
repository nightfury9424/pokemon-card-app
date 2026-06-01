package com.fury.back.domain.inquiry;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.Set;

@Tag(name = "Inquiry", description = "고객 문의")
@RestController
@RequestMapping("/api/inquiries")
@RequiredArgsConstructor
public class InquiryController {

    private static final Set<String> VALID_CATEGORIES = Set.of(
            "cardAddRequest", "price", "trade", "account", "bug", "feature", "etc");

    private final InquiryRepository inquiryRepository;
    private final JwtUtil jwtUtil;

    @Operation(summary = "문의 등록", description = "메일 대신 DB 저장 → 관리자 페이지 처리")
    @PostMapping
    public ReturnData<Map<String, String>> create(
            HttpServletRequest request,
            @RequestBody Map<String, Object> body) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.fail("F403", "인증이 필요합니다.");

        final Map<String, Object> data;
        if (body.get("data") instanceof Map<?, ?> nested) {
            @SuppressWarnings("unchecked")
            final Map<String, Object> casted = (Map<String, Object>) nested;
            data = casted;
        } else {
            data = body;
        }

        String category = data.get("category") != null ? String.valueOf(data.get("category")) : "etc";
        String title = data.get("title") != null ? String.valueOf(data.get("title")).trim() : "";
        String content = data.get("content") != null ? String.valueOf(data.get("content")).trim() : "";
        String contactEmail = data.get("contactEmail") != null ? String.valueOf(data.get("contactEmail")) : null;

        if (!VALID_CATEGORIES.contains(category)) category = "etc";
        if (title.isBlank()) return ReturnData.badRequest("제목을 입력해 주세요.");
        if (content.isBlank()) return ReturnData.badRequest("문의 내용을 입력해 주세요.");
        if (content.length() > 5000) content = content.substring(0, 5000);
        if (title.length() > 200) title = title.substring(0, 200);

        Inquiry inquiry = Inquiry.builder()
                .inquiryId(IdGenerator.generate())
                .userId(userId)
                .category(category)
                .title(title)
                .content(content)
                .contactEmail(contactEmail)
                .status("OPEN")
                .build();
        Inquiry saved = inquiryRepository.save(inquiry);
        return ReturnData.success(Map.of("inquiryId", saved.getInquiryId()));
    }

    @Operation(summary = "내 문의 내역")
    @GetMapping("/me")
    public ReturnData<List<Inquiry>> getMine(HttpServletRequest request) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.success(List.of());
        return ReturnData.success(inquiryRepository.findByUserIdOrderByCreatedAtDesc(userId));
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
