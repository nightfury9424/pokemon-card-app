package com.fury.back.domain.product;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface ProductRepository extends JpaRepository<Product, String> {
    List<Product> findByLanguage(String language);

    List<Product> findBySeriesName(String seriesName);
}
