package com.fury.back.domain.price;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.price.dto.PriceOrderBookDto;
import com.fury.back.domain.price.dto.PriceOrderDto;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@Tag(name = "PriceOrder", description = "호가 (매수/매도 주문) API")
@RestController
@RequestMapping("/api/price-orders")
@RequiredArgsConstructor
public class PriceOrderController {

    private final PriceOrderService priceOrderService;

    @Operation(summary = "카드 호가 조회", description = "해당 카드의 매수/매도 호가 목록과 내 호가를 반환합니다.")
    @GetMapping("/cards/{cardId}")
    public ReturnData<PriceOrderBookDto> getOrderBook(
            @PathVariable String cardId,
            @AuthenticationPrincipal String userId) {
        return priceOrderService.getOrderBook(cardId, userId);
    }

    @Operation(summary = "호가 등록", description = "매수 또는 매도 희망 가격을 등록합니다.")
    @PostMapping("/cards/{cardId}")
    public ReturnData<PriceOrderDto> placeOrder(
            @PathVariable String cardId,
            @AuthenticationPrincipal String userId,
            @RequestBody Map<String, Object> body) {
        String orderType = String.valueOf(body.get("orderType"));
        int price = Integer.parseInt(String.valueOf(body.get("price")));
        return priceOrderService.placeOrder(cardId, userId, orderType, price);
    }

    @Operation(summary = "호가 취소")
    @DeleteMapping("/{orderId}")
    public ReturnData<Void> cancelOrder(
            @PathVariable String orderId,
            @AuthenticationPrincipal String userId) {
        return priceOrderService.cancelOrder(orderId, userId);
    }
}
