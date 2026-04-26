package com.fury.back.domain.trade;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.trade.dto.TradePostDto;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.File;
import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;
import java.util.LinkedHashMap;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class TradeServiceImpl implements TradeService {

    private final TradePostRepository tradePostRepository;
    private final CardRepository cardRepository;
    private final UserRepository userRepository;
    private final com.fury.back.domain.asset.AssetRepository assetRepository;

    @Value("${trade.image.dir}")
    private String tradeImageDir;

    @Override
    public ReturnData<Page<TradePostDto>> getTrades(int page, int size, String cardId, String sellerId) {
        PageRequest pageable = PageRequest.of(page, size);
        Page<TradePost> posts;
        if (sellerId != null && !sellerId.isBlank()) {
            posts = tradePostRepository.findBySellerIdOrderByCreatedAtDesc(sellerId, pageable);
        } else if (cardId != null && !cardId.isBlank()) {
            posts = tradePostRepository.findOpenByCardId(cardId, pageable);
        } else {
            posts = tradePostRepository.findByStatusOrderByCreatedAtDesc("OPEN", pageable);
        }

        List<String> sellerIds = posts.stream().map(TradePost::getSellerId).distinct().toList();
        List<String> cardIds = posts.stream().map(TradePost::getCardId).distinct().toList();

        Map<String, User> userMap = userRepository.findAllById(sellerIds)
                .stream().collect(Collectors.toMap(User::getUserId, Function.identity()));
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds)
                .stream().collect(Collectors.toMap(Card::getCardId, Function.identity()));

        Page<TradePostDto> result = posts.map(post ->
                TradePostDto.fromWithDetails(post, userMap.get(post.getSellerId()), cardMap.get(post.getCardId())));
        return ReturnData.success(result);
    }

    @Override
    public ReturnData<TradePostDto> getTrade(String tradeId) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");

        User seller = userRepository.findById(post.getSellerId()).orElse(null);
        Card card = cardRepository.findById(post.getCardId()).orElse(null);
        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> createTrade(String sellerId, ParameterData parameterData) {
        String cardId = parameterData.getString("cardId");
        String title = parameterData.getString("title");
        String description = parameterData.getString("description");
        if (cardId == null || title == null || description == null || description.isBlank()) {
            return ReturnData.badRequest("cardId, title, description은 필수입니다.");
        }

        Card card = cardRepository.findById(cardId).orElse(null);
        if (card == null) return ReturnData.notFound("카드를 찾을 수 없습니다.");

        // 내 자산에 해당 카드가 있어야만 판매 가능
        boolean hasAsset = !assetRepository.findByUserIdAndCardId(sellerId, cardId).isEmpty();
        if (!hasAsset) return ReturnData.badRequest("내 자산에 등록된 카드만 판매할 수 있습니다.");

        TradePost post = TradePost.builder()
                .tradeId(IdGenerator.generate())
                .sellerId(sellerId)
                .cardId(cardId)
                .title(title)
                .description(description)
                .price(parameterData.getInteger("price"))
                .cardStatus(parameterData.getString("cardStatus") != null ? parameterData.getString("cardStatus") : "RAW")
                .gradingCompany(parameterData.getString("gradingCompany"))
                .gradeValue(parameterData.getString("gradeValue"))
                .build();

        tradePostRepository.save(post);

        User seller = userRepository.findById(sellerId).orElse(null);
        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> updateTrade(String tradeId, String userId, ParameterData parameterData) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        post.update(parameterData.getString("title"), parameterData.getString("description"),
                parameterData.getInteger("price"));

        User seller = userRepository.findById(post.getSellerId()).orElse(null);
        Card card = cardRepository.findById(post.getCardId()).orElse(null);
        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    @Override
    @Transactional
    public ReturnData<Void> deleteTrade(String tradeId, String userId) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        tradePostRepository.delete(post);
        return ReturnData.success();
    }

    @Override
    @Transactional
    public ReturnData<TradePostDto> updateStatus(String tradeId, String userId, String status) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        post.updateStatus(status);

        User seller = userRepository.findById(post.getSellerId()).orElse(null);
        Card card = cardRepository.findById(post.getCardId()).orElse(null);
        return ReturnData.success(TradePostDto.fromWithDetails(post, seller, card));
    }

    @Override
    @Transactional
    public ReturnData<String> uploadImage(String tradeId, String userId, MultipartFile file) {
        TradePost post = tradePostRepository.findById(tradeId).orElse(null);
        if (post == null) return ReturnData.notFound("판매글을 찾을 수 없습니다.");
        if (!post.getSellerId().equals(userId)) return ReturnData.fail("F403", "권한이 없습니다.");

        try {
            String ext = getExtension(file.getOriginalFilename());
            String filename = tradeId + ext;
            File dest = new File(tradeImageDir + "/" + filename);
            dest.getParentFile().mkdirs();
            file.transferTo(dest);

            String imageUrl = "/images/trades/" + filename;
            post.updateImageUrl(imageUrl);
            return ReturnData.success(imageUrl);
        } catch (IOException e) {
            return ReturnData.fail("F500", "이미지 저장 실패: " + e.getMessage());
        }
    }

    @Override
    public ReturnData<List<Map<String, Object>>> getCardTradeSummaries(int size) {
        PageRequest pageable = PageRequest.of(0, size);
        List<Object[]> rows = tradePostRepository.findCardTradeSummary(pageable);

        List<String> cardIds = rows.stream().map(r -> (String) r[0]).toList();
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds)
                .stream().collect(Collectors.toMap(Card::getCardId, Function.identity()));

        List<Map<String, Object>> result = rows.stream().map(row -> {
            String cardId = (String) row[0];
            long count = ((Number) row[1]).longValue();
            int avgPrice = ((Number) row[2]).intValue();
            int minPrice = ((Number) row[3]).intValue();
            Card card = cardMap.get(cardId);

            Map<String, Object> item = new java.util.LinkedHashMap<>();
            item.put("cardId", cardId);
            item.put("sellerCount", count);
            item.put("avgPrice", avgPrice);
            item.put("minPrice", minPrice);
            if (card != null) {
                item.put("name", card.getName());
                item.put("rarityCode", card.getRarityCode());
                item.put("imageUrl", card.getImageUrl());
                item.put("jpScrydexRef", card.getJpScrydexRef());
                item.put("enScrydexRef", card.getEnScrydexRef());
            }
            return item;
        }).toList();

        return ReturnData.success(result);
    }

    private String getExtension(String filename) {
        if (filename == null) return ".jpg";
        int idx = filename.lastIndexOf('.');
        return idx >= 0 ? filename.substring(idx) : ".jpg";
    }
}
