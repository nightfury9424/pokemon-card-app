package com.fury.back.domain.trade;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.trade.dto.TradePostDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

@Tag(name = "Trade", description = "카드 판매 거래 API")
@RestController
@RequestMapping("/api/trades")
@RequiredArgsConstructor
public class TradeController {

    private final TradeService tradeService;

    @Operation(summary = "판매 목록 조회", description = "판매 중인 카드 목록을 페이지 단위로 조회합니다.")
    @GetMapping
    public ReturnData<Page<TradePostDto>> getTrades(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(required = false) String cardId,
            @RequestParam(required = false) String sellerId) {
        return tradeService.getTrades(page, size, cardId, sellerId);
    }

    @Operation(summary = "카드별 판매 요약", description = "카드 단위로 묶어 판매자 수·평균가·최저가를 반환합니다.")
    @GetMapping("/cards/summary")
    public ReturnData<java.util.List<java.util.Map<String, Object>>> getCardTradeSummaries(
            @RequestParam(defaultValue = "20") int size) {
        return tradeService.getCardTradeSummaries(size);
    }

    @Operation(summary = "판매글 상세 조회")
    @GetMapping("/{tradeId}")
    public ReturnData<TradePostDto> getTrade(@PathVariable String tradeId) {
        return tradeService.getTrade(tradeId);
    }

    @Operation(summary = "판매글 등록", description = "JWT 인증 필요. 내 카드를 판매 등록합니다.")
    @PostMapping
    public ReturnData<TradePostDto> createTrade(
            @AuthenticationPrincipal String userId,
            @RequestBody ParameterData parameterData) {
        return tradeService.createTrade(userId, parameterData);
    }

    @Operation(summary = "판매글 수정", description = "JWT 인증 필요. 제목/설명/가격 수정.")
    @PutMapping("/{tradeId}")
    public ReturnData<TradePostDto> updateTrade(
            @PathVariable String tradeId,
            @AuthenticationPrincipal String userId,
            @RequestBody ParameterData parameterData) {
        return tradeService.updateTrade(tradeId, userId, parameterData);
    }

    @Operation(summary = "판매글 삭제", description = "JWT 인증 필요.")
    @DeleteMapping("/{tradeId}")
    public ReturnData<Void> deleteTrade(
            @PathVariable String tradeId,
            @AuthenticationPrincipal String userId) {
        return tradeService.deleteTrade(tradeId, userId);
    }

    @Operation(summary = "판매 상태 변경", description = "OPEN / RESERVED / SOLD")
    @PatchMapping("/{tradeId}/status")
    public ReturnData<TradePostDto> updateStatus(
            @PathVariable String tradeId,
            @AuthenticationPrincipal String userId,
            @RequestParam String status) {
        return tradeService.updateStatus(tradeId, userId, status);
    }

    @Operation(summary = "판매글 이미지 업로드", description = "JWT 인증 필요. 판매글에 카드 실물 사진을 업로드합니다.")
    @PostMapping(value = "/{tradeId}/image", consumes = "multipart/form-data")
    public ReturnData<String> uploadImage(
            @PathVariable String tradeId,
            @AuthenticationPrincipal String userId,
            @RequestPart("file") MultipartFile file) {
        return tradeService.uploadImage(tradeId, userId, file);
    }
}
