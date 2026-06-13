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
    private static final int MAX_IMAGES = 5;

    private final InquiryRepository inquiryRepository;
    private final JwtUtil jwtUtil;
    private final com.fury.back.storage.ImageStorageService imageStorage;

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

    @Operation(summary = "문의 사진 첨부", description = "문의 생성 후 사진 업로드(최대 5장). 모든 카테고리 공통.")
    @PostMapping(value = "/{inquiryId}/image", consumes = "multipart/form-data")
    public ReturnData<String> uploadImage(
            HttpServletRequest request,
            @PathVariable String inquiryId,
            @RequestPart("file") org.springframework.web.multipart.MultipartFile file) {
        String userId = extractUserId(request);
        if (userId == null) return ReturnData.fail("F403", "인증이 필요합니다.");
        Inquiry inquiry = inquiryRepository.findById(inquiryId).orElse(null);
        if (inquiry == null) return ReturnData.notFound("문의를 찾을 수 없습니다.");
        if (!inquiry.getUserId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");
        int current = (inquiry.getImageKeys() == null || inquiry.getImageKeys().isBlank())
                ? 0 : inquiry.getImageKeys().split(",").length;
        if (current >= MAX_IMAGES) return ReturnData.badRequest("사진은 최대 " + MAX_IMAGES + "장까지입니다.");
        try {
            String key = imageStorage.store("uploads/inquiry/" + inquiryId, file.getOriginalFilename(), file);
            inquiry.appendImageKey(key);
            inquiryRepository.save(inquiry);
            return ReturnData.success(com.fury.back.storage.StorageKeyUrls.toProxyUrl(key));
        } catch (java.io.IOException e) {
            return ReturnData.fail("F500", "이미지 저장 실패: " + e.getMessage());
        }
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
