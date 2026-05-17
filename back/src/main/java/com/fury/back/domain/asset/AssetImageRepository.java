package com.fury.back.domain.asset;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface AssetImageRepository extends JpaRepository<AssetImage, String> {
    List<AssetImage> findByAssetId(String assetId);
}
