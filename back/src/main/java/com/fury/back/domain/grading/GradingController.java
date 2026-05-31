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

    @Operation(summary = "카드 등급 분석",
            description = "앞/뒷면 이미지 + frame ROI (normalized 0~1) 받아 자체 9단계 등급 + 감점 사유 반환")
    @PostMapping(value = "/analyze", consumes = "multipart/form-data")
    public ReturnData<GradingResultDto> analyze(
            @RequestParam Map<String, MultipartFile> photos,
            @RequestParam(value = "cardId", required = false) String cardId,
            @RequestParam(value = "frame_x", required = false) Double frameX,
            @RequestParam(value = "frame_y", required = false) Double frameY,
            @RequestParam(value = "frame_w", required = false) Double frameW,
            @RequestParam(value = "frame_h", required = false) Double frameH) {
        return gradingService.analyze(photos, cardId, frameX, frameY, frameW, frameH);
    }
}
