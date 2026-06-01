package com.fury.back.domain.grading;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.grading.dto.GradingResultDto;
import com.fury.back.domain.grading.dto.PrecheckResultDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@Tag(name = "Grading", description = "카드 등급 예측 API")
@RestController
@RequestMapping("/api/grading")
@RequiredArgsConstructor
public class GradingController {

    private final GradingService gradingService;

    @Operation(summary = "촬영 품질 게이트 (per-side precheck)",
            description = "앞면 또는 뒷면 한 장 + frame ROI → 촬영 품질 검증 (full analyze X). " +
                    "사용자가 한 장 찍을 때마다 호출해서 OK/재촬영 판단.")
    @PostMapping(value = "/precheck", consumes = "multipart/form-data")
    public ReturnData<PrecheckResultDto> precheck(
            @RequestParam("image") MultipartFile image,
            @RequestParam(value = "side", defaultValue = "front") String side,
            @RequestParam(value = "frame_x", required = false) Double frameX,
            @RequestParam(value = "frame_y", required = false) Double frameY,
            @RequestParam(value = "frame_w", required = false) Double frameW,
            @RequestParam(value = "frame_h", required = false) Double frameH) {
        return gradingService.precheck(image, side, frameX, frameY, frameW, frameH);
    }

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

    @Operation(summary = "분석 근거 이미지 (lazy fetch)",
            description = "P0-C: 결과 상세 sheet 의 토글 view 가 호출. " +
                    "layer: front_original/back_original/front_surface/back_surface/front_whitening/back_whitening")
    @GetMapping("/evidence/{sessionId}/{layer}")
    public ResponseEntity<Resource> evidence(
            @PathVariable String sessionId,
            @PathVariable String layer) {
        Resource body = gradingService.fetchEvidence(sessionId, layer);
        if (body == null) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND).build();
        }
        return ResponseEntity.ok()
                .contentType(MediaType.IMAGE_JPEG)
                .body(body);
    }
}
