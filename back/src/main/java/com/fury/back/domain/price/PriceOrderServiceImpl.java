package com.fury.back.domain.price;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.price.dto.PriceOrderBookDto;
import com.fury.back.domain.price.dto.PriceOrderDto;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class PriceOrderServiceImpl implements PriceOrderService {

    private final PriceOrderRepository priceOrderRepository;

    @Override
    public ReturnData<PriceOrderBookDto> getOrderBook(String cardId, String userId) {
        List<PriceOrderDto> buyOrders = priceOrderRepository
                .findByCardIdAndStatusOrderByPriceDesc(cardId, "OPEN")
                .stream().map(PriceOrderDto::from).limit(10).toList();
        List<PriceOrderDto> sellOrders = priceOrderRepository
                .findByCardIdAndStatusOrderByPriceAsc(cardId, "OPEN")
                .stream().map(PriceOrderDto::from).limit(10).toList();
        List<PriceOrderDto> myOrders = userId == null ? List.of() :
                priceOrderRepository.findByCardIdAndUserIdAndStatus(cardId, userId, "OPEN")
                        .stream().map(PriceOrderDto::from).toList();

        return ReturnData.success(PriceOrderBookDto.builder()
                .buyOrders(buyOrders)
                .sellOrders(sellOrders)
                .myOrders(myOrders)
                .build());
    }

    @Override
    @Transactional
    public ReturnData<PriceOrderDto> placeOrder(String cardId, String userId, String orderType, int price) {
        if (price <= 0) return ReturnData.badRequest("가격은 0보다 커야 합니다.");
        if (!orderType.equals("BUY") && !orderType.equals("SELL"))
            return ReturnData.badRequest("orderType은 BUY 또는 SELL 이어야 합니다.");

        PriceOrder order = PriceOrder.builder()
                .orderId(IdGenerator.generate())
                .cardId(cardId)
                .userId(userId)
                .orderType(orderType)
                .price(price)
                .status("OPEN")
                .build();
        priceOrderRepository.save(order);
        return ReturnData.success(PriceOrderDto.from(order));
    }

    @Override
    @Transactional
    public ReturnData<Void> cancelOrder(String orderId, String userId) {
        PriceOrder order = priceOrderRepository.findById(orderId).orElse(null);
        if (order == null) return ReturnData.notFound("호가를 찾을 수 없습니다.");
        if (!order.getUserId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");
        order.cancel();
        return ReturnData.success();
    }
}
