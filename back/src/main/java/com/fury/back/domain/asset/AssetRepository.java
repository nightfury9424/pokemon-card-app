package com.fury.back.domain.asset;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AssetRepository extends JpaRepository<Asset, String> {
    List<Asset> findByUserId(String userId);

    List<Asset> findByUserIdAndCardId(String userId, String cardId);
}
