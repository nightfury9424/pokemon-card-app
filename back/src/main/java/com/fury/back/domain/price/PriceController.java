package com.fury.back.domain.price;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.price.dto.CardPriceSummaryDto;
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
        - `source`: `BUNJANG` / `NAVER_CAFE` / `SCRYDEX_EN` / `SCRYDEX_JP` / `KO_ESTIMATED`
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
                          "cardStatus": "RAW",
                          "tradedAt": "2026-03-22T15:30:00"
                        },
                        {
                          "priceSnapshotId": "SNAP_002",
                          "cardId": "CRD_ABC123",
                          "source": "KREAM",
                          "price": 540000,
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

    @GetMapping("/coefficient/history")
    public ReturnData<?> getCoefficientHistory(
            @RequestParam(defaultValue = "30") int days) {
        return ReturnData.success(globalPriceService.getCoefficientHistory(days));
    }

    @Operation(summary = "레어도별 계수 조회", description = "레어도 코드(SSR, SAR, AR 등)별 KO/JP 보정계수. 없으면 글로벌 계수 반환.")
    @GetMapping("/coefficient/rarity/{rarityCode}")
    public ReturnData<Double> getCoefficientByRarity(@PathVariable String rarityCode) {
        return ReturnData.success(globalPriceService.getCoefficientForRarity(rarityCode));
    }

    @Operation(summary = "카드 해외 시세 히스토리", description = "SCRYDEX 기준 해외 시세 (KRW 환산)")
    @GetMapping("/cards/{cardId}/global-history")
    public ReturnData<List<PriceSnapshotDto>> getGlobalHistory(
        @Parameter(description = "카드 ID") @PathVariable String cardId) {
        return ReturnData.success(globalPriceService.getGlobalHistory(cardId));
    }

    @Operation(summary = "카드 가격 요약 (단일 집계)", description = "KO mid/low/high + KO/EN/JP 차트 데이터를 한 번에 반환. 상세 화면 전용.")
    @GetMapping("/cards/{cardId}/price-summary")
    public ReturnData<CardPriceSummaryDto> getPriceSummary(@PathVariable String cardId) {
        var result = globalPriceService.getCardPriceSummary(cardId);
        if (result == null) return ReturnData.notFound("카드를 찾을 수 없습니다.");
        return ReturnData.success(result);
    }

    @Operation(summary = "KO 예상가 (저장된 SCRYDEX_EN)", description = "DB에 저장된 최신 SCRYDEX_EN 가격 (KRW). 리스트와 동일한 기준.")
    @GetMapping("/cards/{cardId}/ko-price")
    public ReturnData<Integer> getKoPrice(@PathVariable String cardId) {
        return ReturnData.success(globalPriceService.getStoredKoPrice(cardId));
    }

    @Operation(summary = "KO 예상가 저장", description = "상세 화면에서 계산된 KO 예상가를 DB에 저장 (하루 1번). body: {\"price\": 123456}")
    @PostMapping("/cards/{cardId}/ko-estimate")
    public ReturnData<String> saveKoEstimate(
            @PathVariable String cardId,
            @RequestBody Map<String, Integer> body) {
        Integer price = body.get("price");
        if (price == null || price <= 0) return ReturnData.badRequest("price는 필수입니다.");
        globalPriceService.saveKoEstimatedForCard(cardId, price);
        return ReturnData.success("저장 완료");
    }

    @Operation(summary = "[Admin] 시장 보정 계수 조회")
    @GetMapping("/admin/market-adjustment")
    public ReturnData<Map<String, Object>> getMarketAdjustment() {
        return ReturnData.success(globalPriceService.getMarketAdjustment());
    }

    @Operation(summary = "[Admin] 시장 보정 계수 변경 + KO 예상가 즉시 재계산",
               description = "현재 ko_coef_* 전체에 (newFactor/currentFactor) 비율 적용 후 KO_ESTIMATED 재계산")
    @PostMapping("/admin/market-adjustment")
    public ReturnData<Map<String, Object>> setMarketAdjustment(@RequestParam double factor) {
        return ReturnData.success(globalPriceService.setMarketAdjustment(factor));
    }

    @Operation(summary = "[Admin] KO 예상가 일괄 갱신 (스냅샷 기반)", description = "저장된 SCRYDEX_EN/JP 스냅샷 × 현재 계수로 KO_ESTIMATED 갱신 (오늘 미저장 카드만)")
    @PostMapping("/admin/refresh-ko-estimates")
    public ReturnData<Map<String, Object>> refreshKoEstimates() {
        return ReturnData.success(globalPriceService.refreshKoEstimatesFromSnapshots());
    }

    @Operation(summary = "[Admin] KO 예상가 히스토리 백필", description = "최근 N일 SCRYDEX_EN/JP 일별 스냅샷 기반 KO_ESTIMATED + audit 생성. force=true 시 기존 KO 14일치 삭제(FK CASCADE로 audit 동반 삭제) 후 audit 포함 재생성.")
    @PostMapping("/admin/backfill-ko-history")
    public ReturnData<Map<String, Object>> backfillKoHistory(
            @RequestParam(defaultValue = "14") int days,
            @RequestParam(defaultValue = "false") boolean force) {
        return ReturnData.success(globalPriceService.backfillKoEstimatedHistory(days, force));
    }

    @Operation(summary = "[Admin] KO audit dry-run", description = "DB write 없는 in-memory carry dry-run. buildKoEstimatedSnapshotsWithAudit를 N일치 (max 14) 연속 carry. cardIds (max 50), startDate, endDate 필수. price_snapshots / ko_estimation_audit 모두 저장하지 않음.")
    @PostMapping("/admin/dry-run-audit")
    public ReturnData<Map<String, Object>> dryRunAudit(@RequestBody Map<String, Object> req) {
        @SuppressWarnings("unchecked")
        List<String> cardIds = (List<String>) req.get("cardIds");
        String startStr = (String) req.get("startDate");
        String endStr = (String) req.get("endDate");
        java.time.LocalDate startDate = startStr == null ? null : java.time.LocalDate.parse(startStr);
        java.time.LocalDate endDate = endStr == null ? null : java.time.LocalDate.parse(endStr);
        return ReturnData.success(globalPriceService.dryRunAuditNDays(cardIds, startDate, endDate));
    }

    @Operation(summary = "[Admin] KO 예상가 라이브 갱신", description = "scrydex ref 있는 모든 카드 실시간 조회 → KO_ESTIMATED 저장. 백그라운드 실행, 즉시 반환.")
    @PostMapping("/admin/refresh-ko-live")
    public ReturnData<Map<String, Object>> refreshKoLive() {
        return ReturnData.success(globalPriceService.startRefreshKoEstimatesLive());
    }

    @Operation(summary = "[Admin] EN/JP→KO 비율 재계산", description = "국내 실거래 vs SCRYDEX_EN/JP 비교로 레어도별 en_*/jp_* 계수 재계산.")
    @PostMapping("/admin/recalculate-en-jp-ratios")
    public ReturnData<String> recalculateEnJpRatios() {
        globalPriceService.recalculateEnJpRatios();
        return ReturnData.success("en/jp ratio 재계산 완료");
    }

    @Operation(summary = "KO 예상가 히스토리", description = "카드별 KO_ESTIMATED 일별 시세 히스토리 (차트용)")
    @GetMapping("/cards/{cardId}/ko-history")
    public ReturnData<List<Map<String, Object>>> getKoHistory(
            @PathVariable String cardId,
            @RequestParam(defaultValue = "90") int days) {
        return ReturnData.success(globalPriceService.getKoEstimatedHistory(cardId, days));
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
        description = "등록된 세트 매핑 기반으로 고레어 KO 카드에 pokemontcg.io 카드 ID 매핑")
    @PostMapping("/admin/map-cards")
    public ReturnData<Map<String, Object>> mapCards() {
        return ReturnData.success(globalPriceService.mapCards());
    }

    @Operation(summary = "[Admin] 해외 시세 수집",
        description = "레거시 엔드포인트. 해외 시세 수집은 scrydex 배치 스크립트를 사용합니다.")
    @PostMapping("/admin/fetch-global-prices")
    public ReturnData<Map<String, Object>> fetchGlobalPrices() {
        return ReturnData.success(globalPriceService.fetchAndStorePrices());
    }

    @Operation(summary = "[Admin] 미매핑 고레어 카드 목록",
        description = "scrydex ref가 없는 KO 고레어 카드 목록. productId 파라미터로 특정 세트만 조회 가능")
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
        description = "지정한 cardId 목록의 scrydex ref를 null로 초기화 (잘못된 매핑 삭제용)")
    @PostMapping("/admin/clear-card-mappings")
    public ReturnData<Map<String, Object>> clearCardMappings(
            @RequestBody List<String> cardIds) {
        return ReturnData.success(globalPriceService.clearCardMappings(cardIds));
    }
}
