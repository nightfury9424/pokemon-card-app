package com.fury.back.domain.price.dto;

import com.fury.back.domain.price.PriceOrder;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class PriceOrderDto {
    private String orderId;
    private String cardId;
    private String userId;
    private String orderType;
    private Integer price;
    private String status;
    private LocalDateTime createdAt;

    public static PriceOrderDto from(PriceOrder o) {
        return PriceOrderDto.builder()
                .orderId(o.getOrderId())
                .cardId(o.getCardId())
                .userId(o.getUserId())
                .orderType(o.getOrderType())
                .price(o.getPrice())
                .status(o.getStatus())
                .createdAt(o.getCreatedAt())
                .build();
    }
}
