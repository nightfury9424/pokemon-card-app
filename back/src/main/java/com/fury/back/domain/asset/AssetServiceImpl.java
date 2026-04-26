package com.fury.back.domain.asset;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.asset.dto.AssetDto;
import com.fury.back.domain.asset.dto.PortfolioSummaryDto;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.function.Function;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class AssetServiceImpl implements AssetService {

    private final AssetRepository assetRepository;
    private final CardRepository cardRepository;

    @Override
    public ReturnData<List<AssetDto>> getMyAssets(String userId) {
        if (userId == null || userId.isBlank()) {
            return ReturnData.badRequest("userId는 필수입니다.");
        }
        List<Asset> assets = assetRepository.findByUserId(userId);
        List<String> cardIds = assets.stream().map(Asset::getCardId).distinct().toList();
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds)
                .stream().collect(Collectors.toMap(Card::getCardId, Function.identity()));

        List<AssetDto> result = assets.stream()
                .map(a -> AssetDto.fromWithCard(a, cardMap.get(a.getCardId())))
                .toList();
        return ReturnData.success(result);
    }

    @Override
    public ReturnData<AssetDto> getAsset(String assetId) {
        if (assetId == null || assetId.isBlank()) {
            return ReturnData.badRequest("assetId는 필수입니다.");
        }
        Optional<Asset> asset = assetRepository.findById(assetId);
        return asset.<ReturnData<AssetDto>>map(a -> ReturnData.success(AssetDto.from(a)))
                .orElseGet(() -> ReturnData.notFound("자산을 찾을 수 없습니다. assetId=" + assetId));
    }

    @Override
    @Transactional
    public ReturnData<AssetDto> registerAsset(ParameterData parameterData) {
        String userId  = parameterData.getString("userId");
        String cardId  = parameterData.getString("cardId");
        Integer quantity = parameterData.getInteger("quantity");

        if (userId == null || cardId == null || quantity == null) {
            return ReturnData.badRequest("userId, cardId, quantity는 필수입니다.");
        }

        String purchasedAtStr = parameterData.getString("purchasedAt");
        LocalDate purchasedAt = purchasedAtStr != null ? LocalDate.parse(purchasedAtStr) : null;

        Asset asset = Asset.builder()
                .assetId(IdGenerator.generate())
                .userId(userId)
                .cardId(cardId)
                .quantity(quantity)
                .purchasePrice(parameterData.getInteger("purchasePrice"))
                .cardStatus(parameterData.getString("cardStatus") != null ? parameterData.getString("cardStatus") : "RAW")
                .gradingCompany(parameterData.getString("gradingCompany"))
                .gradeValue(parameterData.getString("gradeValue"))
                .certNumber(parameterData.getString("certNumber"))
                .memo(parameterData.getString("memo"))
                .purchasedAt(purchasedAt)
                .build();

        Asset saved = assetRepository.save(asset);
        return ReturnData.success(AssetDto.from(saved));
    }

    @Override
    @Transactional
    public ReturnData<AssetDto> updateAsset(String assetId, ParameterData parameterData) {
        if (assetId == null || assetId.isBlank()) {
            return ReturnData.badRequest("assetId는 필수입니다.");
        }
        Optional<Asset> optAsset = assetRepository.findById(assetId);
        if (optAsset.isEmpty()) {
            return ReturnData.notFound("자산을 찾을 수 없습니다. assetId=" + assetId);
        }

        Asset asset = optAsset.get();
        String purchasedAtStr = parameterData.getString("purchasedAt");
        LocalDate purchasedAt = purchasedAtStr != null ? LocalDate.parse(purchasedAtStr) : asset.getPurchasedAt();

        asset.update(
                parameterData.getInteger("quantity") != null ? parameterData.getInteger("quantity") : asset.getQuantity(),
                parameterData.getInteger("purchasePrice") != null ? parameterData.getInteger("purchasePrice") : asset.getPurchasePrice(),
                parameterData.getString("memo") != null ? parameterData.getString("memo") : asset.getMemo(),
                purchasedAt
        );
        return ReturnData.success(AssetDto.from(asset));
    }

    @Override
    @Transactional
    public ReturnData<Void> deleteAsset(String assetId) {
        if (assetId == null || assetId.isBlank()) {
            return ReturnData.badRequest("assetId는 필수입니다.");
        }
        Optional<Asset> optAsset = assetRepository.findById(assetId);
        if (optAsset.isEmpty()) {
            return ReturnData.notFound("자산을 찾을 수 없습니다. assetId=" + assetId);
        }
        assetRepository.delete(optAsset.get());
        return ReturnData.success();
    }

    @Override
    public ReturnData<PortfolioSummaryDto> getPortfolioSummary(String userId) {
        if (userId == null || userId.isBlank()) {
            return ReturnData.badRequest("userId는 필수입니다.");
        }
        List<Asset> assets = assetRepository.findByUserId(userId);

        int totalCards = assets.stream().mapToInt(Asset::getQuantity).sum();
        int totalPurchasePrice = assets.stream()
                .filter(a -> a.getPurchasePrice() != null)
                .mapToInt(a -> a.getPurchasePrice() * a.getQuantity())
                .sum();
        long distinctCardCount = assets.stream()
                .map(Asset::getCardId)
                .distinct()
                .count();

        return ReturnData.success(PortfolioSummaryDto.builder()
                .totalCards(totalCards)
                .totalPurchasePrice(totalPurchasePrice)
                .distinctCardCount(distinctCardCount)
                .build());
    }
}
