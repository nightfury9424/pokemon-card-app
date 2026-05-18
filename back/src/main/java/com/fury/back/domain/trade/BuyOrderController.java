package com.fury.back.domain.trade;

import com.fury.back.auth.JwtUtil;
import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.trade.dto.BuyOrderDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * 매수 호가 API ("삽니다"). 4차-Round4-4 Phase 1.
 * 채팅 기반 협상이므로 자동 매칭 X. markMatched는 사용자 수동 호출.
 */
@Tag(name = "BuyOrder", description = "매수 호가 (삽니다)")
@RestController
@RequestMapping("/api/buy-orders")
@RequiredArgsConstructor
public class BuyOrderController {

    private final BuyOrderService buyOrderService;
    private final JwtUtil jwtUtil;

    @Operation(summary = "카드별 매수 호가 list", description = "OPEN 상태, bid 높은 순 (호가창용)")
    @GetMapping("/cards/{cardId}")
    public ReturnData<List<BuyOrderDto>> getByCard(@PathVariable String cardId) {
        return buyOrderService.getByCard(cardId);
    }

    @Operation(summary = "카드별 매수 호가 페이징")
    @GetMapping("/cards/{cardId}/page")
    public ReturnData<Page<BuyOrderDto>> getByCardPaged(
            @PathVariable String cardId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return buyOrderService.getByCardPaged(cardId, page, size);
    }

    @Operation(summary = "내 매수 호가 list", description = "JWT 인증 필요. status 기본 OPEN. cardId 필터(optional).")
    @GetMapping("/me")
    public ReturnData<List<BuyOrderDto>> getMyOrders(
            HttpServletRequest request,
            @RequestParam(required = false) String status,
            @RequestParam(required = false) String cardId) {
        String buyerId = extractUserId(request);
        return buyOrderService.getMyOrders(buyerId, status, cardId);
    }

    @Operation(summary = "전체 OPEN 매수 호가 페이징", description = "거래 탭 매수 list용 — bid 높은 순.")
    @GetMapping
    public ReturnData<Page<BuyOrderDto>> getAllOpen(
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        return buyOrderService.getAllOpen(page, size);
    }

    @Operation(summary = "매수 호가 등록")
    @PostMapping
    public ReturnData<BuyOrderDto> create(
            HttpServletRequest request,
            @RequestBody ParameterData params) {
        String buyerId = extractUserId(request);
        return buyOrderService.create(buyerId, params);
    }

    @Operation(summary = "매수 호가 가격 수정")
    @PatchMapping("/{buyOrderId}/price")
    public ReturnData<BuyOrderDto> updateBidPrice(
            HttpServletRequest request,
            @PathVariable String buyOrderId,
            @RequestBody Map<String, Object> body) {
        String buyerId = extractUserId(request);
        Integer newPrice = body.get("bidPrice") instanceof Number n ? n.intValue() : null;
        return buyOrderService.updateBidPrice(buyOrderId, buyerId, newPrice);
    }

    @Operation(summary = "매수 호가 취소")
    @DeleteMapping("/{buyOrderId}")
    public ReturnData<Void> cancel(
            HttpServletRequest request,
            @PathVariable String buyOrderId) {
        String buyerId = extractUserId(request);
        return buyOrderService.cancel(buyOrderId, buyerId);
    }

    @Operation(summary = "매수 호가 체결 표시", description = "외부 거래 완료 후 buyer가 호출. tradeId는 선택.")
    @PostMapping("/{buyOrderId}/match")
    public ReturnData<BuyOrderDto> markMatched(
            HttpServletRequest request,
            @PathVariable String buyOrderId,
            @RequestBody(required = false) Map<String, Object> body) {
        String buyerId = extractUserId(request);
        String tradeId = (body != null && body.get("tradeId") != null) ? String.valueOf(body.get("tradeId")) : null;
        return buyOrderService.markMatched(buyOrderId, buyerId, tradeId);
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
