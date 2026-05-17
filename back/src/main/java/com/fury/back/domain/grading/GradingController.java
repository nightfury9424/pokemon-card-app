package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingResultDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

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
            @RequestParam(value = "cardId", required = false) String cardId) {
        return gradingService.analyze(photos, cardId);
    }
}
