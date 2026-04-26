package com.fury.back.domain.product.dto;

import com.fury.back.domain.product.Product;
import lombok.Builder;
import lombok.Getter;

@Getter
@Builder
public class ProductDto {
    private String productId;
    private String name;
    private String seriesName;
    private String productType;
    private String language;

    public static ProductDto from(Product product) {
        return ProductDto.builder()
                .productId(product.getProductId())
                .name(product.getName())
                .seriesName(product.getSeriesName())
                .productType(product.getProductType())
                .language(product.getLanguage())
                .build();
    }
}
