package com.fury.back.domain.asset;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AssetImageRepository extends JpaRepository<AssetImage, String> {
    List<AssetImage> findByAssetId(String assetId);

    // Hotfix 10-3: 자산 list 의 cardVerified 일괄 계산용 batch query (N+1 방지).
    List<AssetImage> findByAssetIdIn(List<String> assetIds);

    void deleteByAssetIdAndImageType(String assetId, String imageType);
}
