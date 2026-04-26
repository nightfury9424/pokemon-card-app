package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingResultDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.Map;

@Tag(name = "Grading", description = "카드 등급 예측 API")
@RestController
@RequestMapping("/api/grading")
@RequiredArgsConstructor
public class GradingController {

    private final GradingService gradingService;

    @Operation(summary = "카드 등급 분석", description = "사진 10장을 받아 항목별 점수와 종합 예상 등급 반환")
    @PostMapping(value = "/analyze", consumes = "multipart/form-data")
    public ReturnData<GradingResultDto> analyze(
            @RequestParam Map<String, MultipartFile> photos,
            @RequestParam String userId,
            @RequestParam(required = false) String cardId) {
        return gradingService.analyze(photos, userId, cardId);
    }

    @Operation(summary = "분석 기록 조회")
    @GetMapping("/history")
    public ReturnData<List<GradingResultDto>> getHistory(@RequestParam String userId) {
        return gradingService.getHistory(userId);
    }
}
