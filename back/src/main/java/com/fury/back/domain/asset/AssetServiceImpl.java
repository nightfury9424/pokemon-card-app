package com.fury.back.domain.asset;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.asset.dto.AssetDto;
import com.fury.back.domain.asset.dto.PortfolioSummaryDto;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.price.ExchangeRateClient;
import com.fury.back.domain.price.PriceSnapshot;
import com.fury.back.domain.price.PriceSnapshotRepository;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.ArrayList;
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
    private final AssetImageRepository assetImageRepository;
    private final TradePostRepository tradePostRepository;
    private final PriceSnapshotRepository priceSnapshotRepository;
    private final ExchangeRateClient exchangeRateClient;

    @Value("${asset.grading.image.dir:${user.home}/pokemon-card-app/asset_grading_images}")
    private String assetGradingImageDir;

    @Override
    public ReturnData<List<AssetDto>> getMyAssets(String userId) {
        if (userId == null || userId.isBlank()) {
            return ReturnData.badRequest("userId는 필수입니다.");
        }
        List<Asset> assets = assetRepository.findByUserId(userId);
        List<String> cardIds = assets.stream().map(Asset::getCardId).distinct().toList();
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds)
                .stream().collect(Collectors.toMap(Card::getCardId, Function.identity()));
        List<String> activeStatuses = List.of("OPEN", "RESERVED");
        Map<String, String> openTradeMap = assets.stream()
                .map(Asset::getAssetId)
                .distinct()
                .map(assetId -> tradePostRepository.findByAssetIdAndStatusIn(assetId, activeStatuses).stream().findFirst().orElse(null))
                .filter(t -> t != null)
                .collect(Collectors.toMap(TradePost::getAssetId, TradePost::getTradeId, (a, b) -> a));

        DisplayPriceContext priceCtx = buildDisplayPriceContext(cardIds);

        List<AssetDto> result = assets.stream()
                .map(a -> {
                    DisplayPriceResult dp = resolveDisplayPrice(a, priceCtx);
                    return AssetDto.fromWithCardAndSelling(a, cardMap.get(a.getCardId()), openTradeMap.get(a.getAssetId()))
                            .toBuilder()
                            .displayPrice(dp.price())
                            .displayPriceBasis(dp.basis())
                            .build();
                })
                .toList();
        return ReturnData.success(result);
    }

    @Override
    public ReturnData<AssetDto> getAsset(String assetId) {
        if (assetId == null || assetId.isBlank()) {
            return ReturnData.badRequest("assetId는 필수입니다.");
        }
        Optional<Asset> asset = assetRepository.findById(assetId);
        return asset.<ReturnData<AssetDto>>map(a -> {
                    String activeTradeId = tradePostRepository.findByAssetIdAndStatusIn(a.getAssetId(), List.of("OPEN", "RESERVED"))
                            .stream()
                            .findFirst()
                            .map(TradePost::getTradeId)
                            .orElse(null);
                    DisplayPriceContext priceCtx = buildDisplayPriceContext(List.of(a.getCardId()));
                    DisplayPriceResult dp = resolveDisplayPrice(a, priceCtx);
                    return ReturnData.success(AssetDto.from(a).toBuilder()
                            .isSelling(activeTradeId != null)
                            .activeTradeId(activeTradeId)
                            .displayPrice(dp.price())
                            .displayPriceBasis(dp.basis())
                            .build());
                })
                .orElseGet(() -> ReturnData.notFound("자산을 찾을 수 없습니다. assetId=" + assetId));
    }

    /**
     * 자산 list의 displayPrice 계산을 위한 batch lookup 컨텍스트.
     * RAW: KO=koEstimated, EN/JP=scrydex raw → KRW 환산.
     * GRADED PSA10: enPsa10/jpPsa10 별도 lookup. 다른 등급/회사는 RAW로 폴백.
     */
    private record DisplayPriceContext(
            Map<String, Integer> koPrice,
            Map<String, PriceSnapshot> enSnap,
            Map<String, PriceSnapshot> jpSnap,
            Map<String, PriceSnapshot> enPsa10,
            Map<String, PriceSnapshot> jpPsa10,
            double usdToKrw,
            double jpyToKrw
    ) {}

    /** displayPrice 계산 결과 — 가격 + 출처(basis). */
    private record DisplayPriceResult(Integer price, String basis) {}

    private DisplayPriceContext buildDisplayPriceContext(List<String> cardIds) {
        if (cardIds.isEmpty()) {
            return new DisplayPriceContext(Map.of(), Map.of(), Map.of(), Map.of(), Map.of(), 0, 0);
        }
        Map<String, Integer> ko = priceSnapshotRepository.findLatestKoEstimatedByCardIds(cardIds).stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, PriceSnapshot::getPrice, (a, b) -> a));
        Map<String, PriceSnapshot> en = priceSnapshotRepository.findLatestScrydexEnByCardIds(cardIds).stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, Function.identity(), (a, b) -> a));
        Map<String, PriceSnapshot> jp = priceSnapshotRepository.findLatestScrydexJpByCardIds(cardIds).stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, Function.identity(), (a, b) -> a));
        Map<String, PriceSnapshot> enPsa10 = priceSnapshotRepository.findLatestScrydexEnPsa10ByCardIds(cardIds).stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, Function.identity(), (a, b) -> a));
        Map<String, PriceSnapshot> jpPsa10 = priceSnapshotRepository.findLatestScrydexJpPsa10ByCardIds(cardIds).stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, Function.identity(), (a, b) -> a));
        double usdToKrw = exchangeRateClient.getUsdToKrw();
        double jpyToKrw = exchangeRateClient.getJpyToKrw();
        return new DisplayPriceContext(ko, en, jp, enPsa10, jpPsa10, usdToKrw, jpyToKrw);
    }

    private DisplayPriceResult resolveDisplayPrice(Asset a, DisplayPriceContext ctx) {
        String lang = a.getLanguage() != null ? a.getLanguage() : "KO";
        boolean isGradedPsa10 = "GRADED".equals(a.getCardStatus())
                && "PSA".equals(a.getGradingCompany())
                && "10".equals(a.getGradeValue());

        // 1) GRADED PSA10 — PSA10 snapshot 우선
        if (isGradedPsa10) {
            PriceSnapshot psa10 = switch (lang) {
                case "EN" -> ctx.enPsa10().get(a.getCardId());
                case "JP" -> ctx.jpPsa10().get(a.getCardId());
                default -> null;  // KO PSA10 시세 데이터는 아직 없음
            };
            Integer p = snapshotToKrw(psa10, ctx.usdToKrw(), ctx.jpyToKrw());
            if (p != null && p > 0) {
                return new DisplayPriceResult(p, "PSA10");
            }
        }

        // 2) RAW 시세 — KO=koEstimated, EN/JP=scrydex raw
        Integer rawPrice = switch (lang) {
            case "EN" -> snapshotToKrw(ctx.enSnap().get(a.getCardId()), ctx.usdToKrw(), ctx.jpyToKrw());
            case "JP" -> snapshotToKrw(ctx.jpSnap().get(a.getCardId()), ctx.usdToKrw(), ctx.jpyToKrw());
            default -> ctx.koPrice().get(a.getCardId());
        };
        if (rawPrice == null) {
            return new DisplayPriceResult(null, null);
        }
        // GRADED인데 PSA10 시세 없어서 RAW로 폴백한 경우
        if ("GRADED".equals(a.getCardStatus())) {
            return new DisplayPriceResult(rawPrice, "RAW_FALLBACK");
        }
        return new DisplayPriceResult(rawPrice, "KO".equals(lang) ? "KO_ESTIMATED" : "RAW");
    }

    private Integer snapshotToKrw(PriceSnapshot s, double usdToKrw, double jpyToKrw) {
        if (s == null) return null;
        if (s.getRawPrice() == null || s.getRawCurrency() == null) {
            return s.getPrice();
        }
        return switch (s.getRawCurrency()) {
            case "USD" -> (int) Math.round(s.getRawPrice().doubleValue() * usdToKrw);
            case "JPY" -> (int) Math.round(s.getRawPrice().doubleValue() * jpyToKrw);
            default -> s.getPrice();
        };
    }

    @Override
    @Transactional
    public ReturnData<AssetDto> registerAsset(ParameterData parameterData) {
        String userId  = parameterData.getString("userId");
        String cardId  = parameterData.getString("cardId");
        Integer quantity = parameterData.getInteger("quantity");

        if (userId == null || cardId == null) {
            return ReturnData.badRequest("userId, cardId는 필수입니다.");
        }

        String purchasedAtStr = parameterData.getString("purchasedAt");
        LocalDate purchasedAt = purchasedAtStr != null ? LocalDate.parse(purchasedAtStr) : null;

        String language = normalizeLanguage(parameterData.getString("language"));
        String cardStatus = parameterData.getString("cardStatus") != null ? parameterData.getString("cardStatus") : "RAW";
        String gradingCompany = parameterData.getString("gradingCompany");
        String gradeValue = parameterData.getString("gradeValue");

        Integer purchasePrice = parameterData.getInteger("purchasePrice");
        if (purchasePrice == null) {
            purchasePrice = resolveAutoPurchasePrice(cardId, language, cardStatus, gradingCompany, gradeValue);
        }

        Asset asset = Asset.builder()
                .assetId(IdGenerator.generate())
                .userId(userId)
                .cardId(cardId)
                .quantity(quantity != null ? quantity : 1)
                .purchasePrice(purchasePrice)
                .language(language)
                .cardStatus(cardStatus)
                .gradingCompany(gradingCompany)
                .gradeValue(gradeValue)
                .certNumber(parameterData.getString("certNumber"))
                .estimatedGrade(getBigDecimal(parameterData, "estimatedGrade"))
                .centeringScore(getBigDecimal(parameterData, "centeringScore"))
                .cornerScore(getBigDecimal(parameterData, "cornerScore"))
                .surfaceScore(getBigDecimal(parameterData, "surfaceScore"))
                .whiteningScore(getBigDecimal(parameterData, "whiteningScore"))
                .centeringRatio(parameterData.getString("centeringRatio"))
                .detectionConfidence(getBigDecimal(parameterData, "detectionConfidence"))
                .gradingAnalyzedAt(getBigDecimal(parameterData, "estimatedGrade") != null ? LocalDateTime.now() : null)
                .memo(parameterData.getString("memo"))
                .purchasedAt(purchasedAt)
                .build();

        Asset saved = assetRepository.save(asset);
        DisplayPriceResult dp = resolveDisplayPrice(saved, buildDisplayPriceContext(List.of(saved.getCardId())));
        return ReturnData.success(AssetDto.from(saved).toBuilder()
                .displayPrice(dp.price())
                .displayPriceBasis(dp.basis())
                .build());
    }

    private String normalizeLanguage(String language) {
        if (language == null || language.isBlank()) {
            return "KO";
        }
        return switch (language.toUpperCase()) {
            case "EN" -> "EN";
            case "JP" -> "JP";
            default -> "KO";
        };
    }

    private Integer resolveAutoPurchasePrice(
            String cardId,
            String language,
            String cardStatus,
            String gradingCompany,
            String gradeValue
    ) {
        DisplayPriceContext priceCtx = buildDisplayPriceContext(List.of(cardId));
        Asset priceProbe = Asset.builder()
                .cardId(cardId)
                .quantity(1)
                .language(language)
                .cardStatus(cardStatus)
                .gradingCompany(gradingCompany)
                .gradeValue(gradeValue)
                .build();
        // 자동 구매가는 현재 displayPrice와 동일 언어/동일 등급 기준으로 채워야 손익률이 왜곡되지 않는다.
        return resolveDisplayPrice(priceProbe, priceCtx).price();
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
    public void updateGradingInfo(String assetId, String gradingCompany, String gradeValue) {
        if (assetId == null || assetId.isBlank()) {
            throw new IllegalArgumentException("assetId는 필수입니다.");
        }
        if (!"PSA".equals(gradingCompany) && !"BRG".equals(gradingCompany)) {
            throw new IllegalArgumentException("감정사는 PSA 또는 BRG만 가능합니다.");
        }
        if (gradeValue == null || gradeValue.isBlank()) {
            throw new IllegalArgumentException("gradeValue는 필수입니다.");
        }
        Asset asset = assetRepository.findById(assetId)
                .orElseThrow(() -> new IllegalArgumentException("자산을 찾을 수 없습니다. assetId=" + assetId));
        asset.setGradingCompany(gradingCompany);
        asset.setGradeValue(gradeValue);
        assetRepository.save(asset);
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
        boolean hasActiveTrade = tradePostRepository.existsByAssetIdAndStatusIn(assetId, List.of("OPEN", "RESERVED"));
        if (hasActiveTrade) {
            throw new IllegalStateException("판매 중인 자산은 삭제할 수 없습니다. assetId=" + assetId);
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
        DisplayPriceContext priceCtx = buildDisplayPriceContext(
                assets.stream().map(Asset::getCardId).distinct().toList()
        );
        int totalMarketValue = assets.stream()
                .map(a -> {
                    Integer price = resolveDisplayPrice(a, priceCtx).price();
                    return price == null ? 0 : price * a.getQuantity();
                })
                .mapToInt(Integer::intValue)
                .sum();
        long distinctCardCount = assets.stream()
                .map(Asset::getCardId)
                .distinct()
                .count();

        return ReturnData.success(PortfolioSummaryDto.builder()
                .totalCards(totalCards)
                .totalPurchasePrice(totalPurchasePrice)
                .totalMarketValue(totalMarketValue)
                .distinctCardCount(distinctCardCount)
                .build());
    }

    @Override
    @Transactional
    public ReturnData<List<String>> saveGradingResult(String assetId, AssetDto.GradingResultRequest req,
                                                      MultipartFile frontImage, MultipartFile backImage) {
        if (assetId == null || assetId.isBlank()) {
            return ReturnData.badRequest("assetId는 필수입니다.");
        }
        if (req == null) {
            return ReturnData.badRequest("그레이딩 결과는 필수입니다.");
        }
        if (frontImage == null || frontImage.isEmpty() || backImage == null || backImage.isEmpty()) {
            return ReturnData.badRequest("front_image, back_image는 필수입니다.");
        }

        Asset asset = assetRepository.findById(assetId).orElse(null);
        if (asset == null) {
            return ReturnData.notFound("자산을 찾을 수 없습니다. assetId=" + assetId);
        }

        asset.updateGradingResult(
                req.estimatedGrade(),
                req.centeringScore(),
                req.cornerScore(),
                req.surfaceScore(),
                req.whiteningScore(),
                req.centeringRatio(),
                req.detectionConfidence()
        );
        asset.updateCertNumberIfEmpty(req.appAnalysisId());

        try {
            String frontFilename = assetId + "_front.jpg";
            String backFilename = assetId + "_back.jpg";
            saveImage(frontImage, frontFilename);
            saveImage(backImage, backFilename);

            List<String> imageUrls = new ArrayList<>();
            imageUrls.add("/images/asset-grading/" + frontFilename);
            imageUrls.add("/images/asset-grading/" + backFilename);

            assetImageRepository.save(AssetImage.of(assetId, "FRONT", imageUrls.get(0)));
            assetImageRepository.save(AssetImage.of(assetId, "BACK", imageUrls.get(1)));

            return ReturnData.success(imageUrls);
        } catch (IOException e) {
            return ReturnData.fail("F500", "이미지 저장 실패: " + e.getMessage());
        }
    }

    private void saveImage(MultipartFile image, String filename) throws IOException {
        File dest = new File(assetGradingImageDir + "/" + filename);
        dest.getParentFile().mkdirs();
        image.transferTo(dest);
    }

    @Override
    @Transactional
    public void uploadSlabImage(Long assetId, MultipartFile file) throws IOException {
        if (assetId == null) {
            throw new IOException("assetId는 필수입니다.");
        }
        uploadSlabImage(String.valueOf(assetId), file);
    }

    @Override
    @Transactional
    public void uploadSlabImage(String assetId, MultipartFile file) throws IOException {
        if (assetId == null || assetId.isBlank()) {
            throw new IOException("assetId는 필수입니다.");
        }
        if (file == null || file.isEmpty()) {
            throw new IOException("slab_image는 필수입니다.");
        }
        Asset asset = assetRepository.findById(assetId)
                .orElseThrow(() -> new IOException("자산을 찾을 수 없습니다. assetId=" + assetId));

        String filename = "slab_" + assetId + "_" + System.currentTimeMillis() + getExtension(file.getOriginalFilename());
        saveImage(file, filename);
        assetImageRepository.save(AssetImage.of(asset.getAssetId(), "SLAB", "/images/asset-grading/" + filename));
    }

    private String getExtension(String filename) {
        if (filename == null || filename.isBlank()) return ".jpg";
        int idx = filename.lastIndexOf('.');
        return idx >= 0 ? filename.substring(idx) : ".jpg";
    }

    @Override
    public ReturnData<List<Map<String, String>>> getAssetImages(String assetId) {
        if (assetId == null || assetId.isBlank()) {
            return ReturnData.badRequest("assetId는 필수입니다.");
        }
        List<AssetImage> images = assetImageRepository.findByAssetId(assetId);
        List<Map<String, String>> result = images.stream()
                .map(img -> Map.of(
                        "imageId", img.getImageId(),
                        "imageType", img.getImageType(),
                        "imageUrl", img.getImageUrl()
                ))
                .toList();
        return ReturnData.success(result);
    }

    private BigDecimal getBigDecimal(ParameterData parameterData, String key) {
        String value = parameterData.getString(key);
        if (value == null || value.isBlank()) return null;
        try {
            return new BigDecimal(value);
        } catch (NumberFormatException e) {
            return null;
        }
    }
}
