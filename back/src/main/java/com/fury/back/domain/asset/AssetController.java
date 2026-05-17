package com.fury.back.domain.asset;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.asset.dto.AssetDto;
import com.fury.back.domain.asset.dto.PortfolioSummaryDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.math.BigDecimal;
import java.util.List;
import java.util.Map;

@Tag(name = "Asset", description = "자산(보유 카드) 관리 및 포트폴리오 API")
@RestController
@RequestMapping("/api/assets")
@RequiredArgsConstructor
public class AssetController {

    private final AssetService assetService;

    @Operation(summary = "내 자산 목록 조회", description = "userId에 해당하는 전체 보유 카드 자산 목록을 반환합니다.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": [
                        {
                          "assetId": "ASSET_001", "userId": "USR_ABC",
                          "cardId": "CRD_ABC123", "quantity": 2,
                          "purchasePrice": 85000, "cardStatus": "RAW",
                          "memo": "직거래 구매", "purchasedAt": "2026-03-01"
                        }
                      ]
                    }""")))
    })
    @GetMapping
    public ReturnData<List<AssetDto>> getMyAssets(
        @Parameter(description = "사용자 ID", example = "USR_ABC")
        @RequestParam String userId) {
        return assetService.getMyAssets(userId);
    }

    @Operation(summary = "자산 단건 조회", description = "assetId로 자산을 조회합니다.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": { "assetId": "ASSET_001", "cardId": "CRD_ABC123", "quantity": 1 }
                    }""")))
    })
    @GetMapping("/{assetId}")
    public ReturnData<AssetDto> getAsset(
        @Parameter(description = "자산 ID", example = "ASSET_001")
        @PathVariable String assetId) {
        return assetService.getAsset(assetId);
    }

    @Operation(summary = "자산 등록", description = """
        카드를 내 자산으로 등록합니다.
        - `cardStatus`: `RAW` (기본값) / `GRADED`
        - 그레이딩 카드는 `gradingCompany`, `gradeValue`, `certNumber` 추가 입력
        """)
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "등록 성공",
            content = @Content(mediaType = "application/json", examples = {
                @ExampleObject(name = "일반 카드", value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": { "assetId": "ASSET_001", "cardId": "CRD_ABC123", "quantity": 1, "cardStatus": "RAW" }
                    }"""),
                @ExampleObject(name = "그레이딩 카드", value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": { "assetId": "ASSET_002", "cardStatus": "GRADED", "gradingCompany": "PSA", "gradeValue": "10" }
                    }""")
            }))
    })
    @PostMapping
    public ReturnData<AssetDto> registerAsset(
        @RequestBody
        @io.swagger.v3.oas.annotations.parameters.RequestBody(
            description = "자산 등록 요청",
            content = @Content(examples = {
                @ExampleObject(name = "일반 카드", value = """
                    {
                      "data": {
                        "userId": "USR_ABC",
                        "cardId": "CRD_ABC123",
                        "quantity": 1,
                        "purchasePrice": 90000,
                        "cardStatus": "RAW",
                        "memo": "번개장터 구매",
                        "purchasedAt": "2026-03-23"
                      }
                    }"""),
                @ExampleObject(name = "그레이딩 카드", value = """
                    {
                      "data": {
                        "userId": "USR_ABC",
                        "cardId": "CRD_XYZ789",
                        "quantity": 1,
                        "purchasePrice": 520000,
                        "cardStatus": "GRADED",
                        "gradingCompany": "PSA",
                        "gradeValue": "10",
                        "certNumber": "12345678",
                        "purchasedAt": "2026-03-23"
                      }
                    }""")
            }))
        ParameterData parameterData) {
        return assetService.registerAsset(parameterData);
    }

    @Operation(summary = "자산 수정", description = "수량, 매입가, 메모, 구매일 수정이 가능합니다.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "수정 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": { "assetId": "ASSET_001", "quantity": 3, "purchasePrice": 82000 }
                    }""")))
    })
    @PutMapping("/{assetId}")
    public ReturnData<AssetDto> updateAsset(
        @Parameter(description = "자산 ID", example = "ASSET_001")
        @PathVariable String assetId,
        @RequestBody
        @io.swagger.v3.oas.annotations.parameters.RequestBody(
            description = "자산 수정 요청",
            content = @Content(examples = @ExampleObject(value = """
                {
                  "data": {
                    "quantity": 3,
                    "purchasePrice": 82000,
                    "memo": "추가 구매 후 수정",
                    "purchasedAt": "2026-03-20"
                  }
                }""")))
        ParameterData parameterData) {
        return assetService.updateAsset(assetId, parameterData);
    }

    @Operation(summary = "외부 감정 정보 저장", description = "자산에 외부 감정사와 등급 값을 저장합니다.")
    @PatchMapping("/{assetId}/grading-info")
    @SuppressWarnings("unchecked")
    public ReturnData<Void> updateGradingInfo(
            @Parameter(description = "자산 ID", example = "ASSET_001")
            @PathVariable String assetId,
            @RequestBody Map<String, Object> body) {
        Map<String, Object> data = body.get("data") instanceof Map<?, ?> nested
                ? (Map<String, Object>) nested
                : body;
        try {
            assetService.updateGradingInfo(
                    assetId,
                    data.get("gradingCompany") == null ? null : String.valueOf(data.get("gradingCompany")),
                    data.get("gradeValue") == null ? null : String.valueOf(data.get("gradeValue"))
            );
            return ReturnData.success();
        } catch (IllegalArgumentException e) {
            return ReturnData.badRequest(e.getMessage());
        }
    }

    @Operation(summary = "자산 삭제", description = "assetId에 해당하는 자산을 삭제합니다.")
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "삭제 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    { "status": "success", "code": "S000", "message": "성공", "data": null }""")))
    })
    @DeleteMapping("/{assetId}")
    public ReturnData<Void> deleteAsset(
        @Parameter(description = "자산 ID", example = "ASSET_001")
        @PathVariable String assetId) {
        return assetService.deleteAsset(assetId);
    }

    @Operation(summary = "포트폴리오 요약 조회", description = """
        사용자의 전체 자산 현황 요약을 반환합니다.
        - `totalCards`: 전체 보유 카드 수 (수량 합산)
        - `totalPurchasePrice`: 전체 매입금액 (원)
        - `distinctCardCount`: 보유 카드 종류 수 (중복 제외)
        """)
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": {
                        "totalCards": 12,
                        "totalPurchasePrice": 1850000,
                        "distinctCardCount": 7
                      }
                    }""")))
    })
    @GetMapping("/portfolio")
    public ReturnData<PortfolioSummaryDto> getPortfolioSummary(
        @Parameter(description = "사용자 ID", example = "USR_ABC")
        @RequestParam String userId) {
        return assetService.getPortfolioSummary(userId);
    }

    @Operation(summary = "자산 이미지 목록 조회", description = "자산에 저장된 FRONT/BACK/SLAB 이미지 목록을 반환합니다.")
    @GetMapping("/{assetId}/images")
    public ReturnData<List<Map<String, String>>> getAssetImages(
            @Parameter(description = "자산 ID", example = "ASSET_001")
            @PathVariable String assetId) {
        return assetService.getAssetImages(assetId);
    }

    @Operation(summary = "자산 그레이딩 결과 저장", description = "자산에 앱 분석 점수와 앞/뒤 이미지를 저장합니다.")
    @PostMapping(value = "/{assetId}/grading", consumes = "multipart/form-data")
    public ReturnData<List<String>> saveGradingResult(
            @Parameter(description = "자산 ID", example = "ASSET_001")
            @PathVariable String assetId,
            @RequestParam("front_image") MultipartFile frontImage,
            @RequestParam("back_image") MultipartFile backImage,
            @RequestParam("estimated_grade") BigDecimal estimatedGrade,
            @RequestParam("centering_score") BigDecimal centeringScore,
            @RequestParam("corner_score") BigDecimal cornerScore,
            @RequestParam("surface_score") BigDecimal surfaceScore,
            @RequestParam("whitening_score") BigDecimal whiteningScore,
            @RequestParam(value = "centering_ratio", required = false) String centeringRatio,
            @RequestParam("detection_confidence") BigDecimal detectionConfidence,
            @RequestParam(value = "app_analysis_id", required = false) String appAnalysisId,
            @RequestParam(value = "cardStatus", required = false) String cardStatus) {
        return assetService.saveGradingResult(
                assetId,
                new AssetDto.GradingResultRequest(
                        estimatedGrade,
                        centeringScore,
                        cornerScore,
                        surfaceScore,
                        whiteningScore,
                        centeringRatio,
                        detectionConfidence,
                        appAnalysisId
                ),
                frontImage,
                backImage
        );
    }

    @Operation(summary = "외부 감정 슬랩 이미지 업로드", description = "외부 감정 카드의 슬랩 사진을 업로드합니다.")
    @PostMapping(value = "/{assetId}/slab-image", consumes = "multipart/form-data")
    public ResponseEntity<Void> uploadSlabImage(
            @Parameter(description = "자산 ID", example = "ASSET_001")
            @PathVariable String assetId,
            @RequestParam("slab_image") MultipartFile slabImage) throws IOException {
        assetService.uploadSlabImage(assetId, slabImage);
        return ResponseEntity.ok().build();
    }
}
