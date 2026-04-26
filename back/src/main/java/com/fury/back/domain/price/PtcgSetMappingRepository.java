package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface PtcgSetMappingRepository extends JpaRepository<PtcgSetMapping, String> {
    List<PtcgSetMapping> findAll();
}
