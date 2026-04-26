package com.fury.back.domain.price;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.price.dto.MarketCoefficientDto;
import com.fury.back.domain.price.dto.PriceSnapshotDto;
import com.fury.back.domain.price.dto.PriceSummaryDto;
import com.fury.back.domain.price.dto.ScrydexHistoryDto;
import com.fury.back.domain.price.dto.ScrydexLivePriceDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.ExampleObject;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@Tag(name = "Price", description = "카드 시세 조회 API")
@RestController
@RequestMapping("/api/prices")
@RequiredArgsConstructor
public class PriceController {

    private final PriceService priceService;
    private final GlobalPriceService globalPriceService;

    @Operation(summary = "카드 시세 요약 조회", description = """
        카드의 집계 시세 정보를 조회합니다.
        - `period`: `7D` (7일), `30D` (30일)
        - `cardStatus`: `RAW` (일반), `GRADED` (그레이딩)
        - 그레이딩 카드는 `gradingCompany` + `gradeValue` 조합으로 구분됩니다.
        """)
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": [
                        {
                          "priceSummaryId": "SUM_001",
                          "cardId": "CRD_ABC123",
                          "cardStatus": "RAW",
                          "period": "7D",
                          "medianPrice": 85000,
                          "avgPrice": 88000,
                          "minPrice": 70000,
                          "maxPrice": 110000,
                          "tradeCount": 12
                        },
                        {
                          "priceSummaryId": "SUM_002",
                          "cardId": "CRD_ABC123",
                          "cardStatus": "GRADED",
                          "gradingCompany": "PSA",
                          "gradeValue": "10",
                          "period": "7D",
                          "medianPrice": 550000,
                          "tradeCount": 3
                        }
                      ]
                    }""")))
    })
    @GetMapping("/cards/{cardId}")
    public ReturnData<List<PriceSummaryDto>> getSummaries(
        @Parameter(description = "카드 ID", example = "CRD_ABC123")
        @PathVariable String cardId) {
        return priceService.getSummaries(cardId);
    }

    @Operation(summary = "카드 시세 히스토리 조회 (최근 30일)", description = """
        수집된 원천 시세 데이터를 반환합니다. (최근 30일)
        - `source`: `NAVER_SHOPPING` / `KREAM` / `BUNJANG` / `NAVER_CAFE` / `ICU` / `JOONGGONARA` / `APP`
        """)
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "조회 성공",
            content = @Content(mediaType = "application/json", examples =
                @ExampleObject(value = """
                    {
                      "status": "success", "code": "S000", "message": "성공",
                      "data": [
                        {
                          "priceSnapshotId": "SNAP_001",
                          "cardId": "CRD_ABC123",
                          "source": "BUNJANG",
                          "price": 90000,
                          "currency": "KRW",
                          "cardStatus": "RAW",
                          "tradedAt": "2026-03-22T15:30:00"
                        },
                        {
                          "priceSnapshotId": "SNAP_002",
                          "cardId": "CRD_ABC123",
                          "source": "KREAM",
                          "price": 540000,
                          "currency": "KRW",
                          "cardStatus": "GRADED",
                          "gradingCompany": "PSA",
                          "gradeValue": "10",
                          "tradedAt": "2026-03-21T10:00:00"
                        }
                      ]
                    }""")))
    })
    @GetMapping("/cards/{cardId}/history")
    public ReturnData<List<PriceSnapshotDto>> getHistory(
        @Parameter(description = "카드 ID", example = "CRD_ABC123")
        @PathVariable String cardId) {
        return priceService.getRecentSnapshots(cardId);
    }

    // ─────────────────────────────────────────────
    // 해외 시세 / 시장 계수
    // ─────────────────────────────────────────────

    @Operation(summary = "한국 시장 계수 조회",
        description = "고레어 카드 기준 한국 시세 / 해외 시세 비율. 예: 0.52 → 한국이 해외 대비 52% 수준")
    @GetMapping("/coefficient")
    public ReturnData<MarketCoefficientDto> getCoefficient() {
        return ReturnData.success(globalPriceService.getCoefficient());
    }

    @Operation(summary = "카드 해외 시세 히스토리", description = "TCGPlayer 기준 해외 시세 (KRW 환산)")
    @GetMapping("/cards/{cardId}/global-history")
    public ReturnData<List<PriceSnapshotDto>> getGlobalHistory(
        @Parameter(description = "카드 ID") @PathVariable String cardId) {
        return ReturnData.success(globalPriceService.getGlobalHistory(cardId));
    }

    @Operation(summary = "scrydex 히스토리", description = "RAW NM + PSA 10/9 일별 가격 히스토리. source=EN(기본) 또는 JP")
    @GetMapping("/cards/{cardId}/scrydex-history")
    public ReturnData<ScrydexHistoryDto> getScrydexHistory(
            @Parameter(description = "카드 ID") @PathVariable String cardId,
            @Parameter(description = "EN 또는 JP") @RequestParam(defaultValue = "EN") String source) {
        return globalPriceService.getScrydexHistory(cardId, source)
                .map(ReturnData::success)
                .orElse(ReturnData.success(null));
    }

    @Operation(summary = "scrydex 실시간 가격", description = "RAW Near Mint + PSA 9/10 최신 eBay 판매가 (USD, 1시간 캐시)")
    @GetMapping("/cards/{cardId}/scrydex-live")
    public ReturnData<ScrydexLivePriceDto> getScrydexLive(
        @Parameter(description = "카드 ID") @PathVariable String cardId) {
        return globalPriceService.getScrydexLivePrice(cardId)
                .map(ReturnData::success)
                .orElse(ReturnData.success(null));
    }

    // ─────────────────────────────────────────────
    // 어드민 - 데이터 수집
    // ─────────────────────────────────────────────

    @Operation(summary = "[Admin] 세트 매핑 등록",
        description = "productId → pokemontcg.io 세트 ID 매핑 저장. mappings: {\"PROD_001\": \"swsh12pt5\", ...}")
    @PostMapping("/admin/set-mapping")
    public ReturnData<String> saveSetMapping(@RequestBody Map<String, String> mappings) {
        globalPriceService.saveSetMappings(mappings);
        return ReturnData.success("세트 매핑 " + mappings.size() + "건 저장 완료");
    }

    @Operation(summary = "[Admin] 카드 매핑 실행",
        description = "등록된 세트 매핑 기반으로 고레어 KO 카드에 TCGPlayer 카드 ID 매핑")
    @PostMapping("/admin/map-cards")
    public ReturnData<Map<String, Object>> mapCards() {
        return ReturnData.success(globalPriceService.mapCards());
    }

    @Operation(summary = "[Admin] 해외 시세 수집",
        description = "매핑된 고레어 카드의 TCGPlayer USD 시세를 KRW 환산하여 저장 (하루 1회)")
    @PostMapping("/admin/fetch-global-prices")
    public ReturnData<Map<String, Object>> fetchGlobalPrices() {
        return ReturnData.success(globalPriceService.fetchAndStorePrices());
    }

    @Operation(summary = "[Admin] 미매핑 고레어 카드 목록",
        description = "tcgplayer_card_id가 없는 KO 고레어 카드 목록. productId 파라미터로 특정 세트만 조회 가능")
    @GetMapping("/admin/unmapped-cards")
    public ReturnData<List<Map<String, Object>>> getUnmappedCards(
            @RequestParam(required = false) String productId) {
        return ReturnData.success(globalPriceService.getUnmappedHighRareCards(productId));
    }

    @Operation(summary = "[Admin] 수동 카드 매핑",
        description = "cardId → pokemontcg.io 카드 ID 직접 지정. 예: {\"CRD_xxx\": \"sv5-123\"}")
    @PostMapping("/admin/manual-card-mapping")
    public ReturnData<Map<String, Object>> saveManualCardMappings(
            @RequestBody Map<String, String> mappings) {
        return ReturnData.success(globalPriceService.saveManualCardMappings(mappings));
    }

    @Operation(summary = "[Admin] 카드 매핑 초기화",
        description = "지정한 cardId 목록의 tcgplayer_card_id를 null로 초기화 (잘못된 매핑 삭제용)")
    @PostMapping("/admin/clear-card-mappings")
    public ReturnData<Map<String, Object>> clearCardMappings(
            @RequestBody List<String> cardIds) {
        return ReturnData.success(globalPriceService.clearCardMappings(cardIds));
    }
}
