package com.fury.back.domain.price;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.price.dto.PriceOrderBookDto;
import com.fury.back.domain.price.dto.PriceOrderDto;

public interface PriceOrderService {
    ReturnData<PriceOrderBookDto> getOrderBook(String cardId, String userId);
    ReturnData<PriceOrderDto> placeOrder(String cardId, String userId, String orderType, int price);
    ReturnData<Void> cancelOrder(String orderId, String userId);
}
