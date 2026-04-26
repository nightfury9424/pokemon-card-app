package com.fury.back.domain.product;

import com.fury.back.common.ReturnData;
import com.fury.back.domain.product.dto.ProductDto;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Tag(name = "Product", description = "팩(상품) 조회 API")
@RestController
@RequestMapping("/api/products")
@RequiredArgsConstructor
public class ProductController {

    private final ProductRepository productRepository;

    @GetMapping
    public ReturnData<List<ProductDto>> getProducts(
            @RequestParam(defaultValue = "KO") String language) {
        List<ProductDto> result = productRepository.findByLanguage(language)
                .stream()
                .map(ProductDto::from)
                .toList();
        return ReturnData.success(result);
    }
}
