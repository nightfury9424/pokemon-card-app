package com.fury.back.domain.price.dto;

import lombok.Builder;
import lombok.Getter;

import java.util.List;

@Getter
@Builder
public class PriceOrderBookDto {
    private List<PriceOrderDto> buyOrders;
    private List<PriceOrderDto> sellOrders;
    private List<PriceOrderDto> myOrders;
}
