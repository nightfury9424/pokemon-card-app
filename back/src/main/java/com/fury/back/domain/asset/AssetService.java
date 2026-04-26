package com.fury.back.domain.asset;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.asset.dto.AssetDto;
import com.fury.back.domain.asset.dto.PortfolioSummaryDto;

import java.util.List;

public interface AssetService {
    ReturnData<List<AssetDto>> getMyAssets(String userId);
    ReturnData<AssetDto> getAsset(String assetId);
    ReturnData<AssetDto> registerAsset(ParameterData parameterData);
    ReturnData<AssetDto> updateAsset(String assetId, ParameterData parameterData);
    ReturnData<Void> deleteAsset(String assetId);
    ReturnData<PortfolioSummaryDto> getPortfolioSummary(String userId);
}
