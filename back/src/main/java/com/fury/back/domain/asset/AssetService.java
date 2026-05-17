package com.fury.back.domain.asset;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.asset.dto.AssetDto;
import com.fury.back.domain.asset.dto.PortfolioSummaryDto;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;

public interface AssetService {
    ReturnData<List<AssetDto>> getMyAssets(String userId);
    ReturnData<AssetDto> getAsset(String assetId);
    ReturnData<AssetDto> registerAsset(ParameterData parameterData);
    ReturnData<AssetDto> updateAsset(String assetId, ParameterData parameterData);
    void updateGradingInfo(String assetId, String gradingCompany, String gradeValue);
    ReturnData<Void> deleteAsset(String assetId);
    ReturnData<PortfolioSummaryDto> getPortfolioSummary(String userId);
    ReturnData<List<String>> saveGradingResult(String assetId, AssetDto.GradingResultRequest req,
                                               MultipartFile frontImage, MultipartFile backImage);
    void uploadSlabImage(Long assetId, MultipartFile file) throws IOException;
    void uploadSlabImage(String assetId, MultipartFile file) throws IOException;
    ReturnData<List<java.util.Map<String, String>>> getAssetImages(String assetId);
}
