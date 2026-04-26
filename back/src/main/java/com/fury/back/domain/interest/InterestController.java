package com.fury.back.domain.interest;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.domain.trade.TradePost;
import com.fury.back.domain.trade.TradePostRepository;
import com.fury.back.domain.user.User;
import com.fury.back.domain.user.UserRepository;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

@Tag(name = "Interest", description = "관심(찜) API")
@RestController
@RequestMapping("/api/interests")
@RequiredArgsConstructor
public class InterestController {

    private final PostInterestRepository interestRepository;
    private final TradePostRepository tradePostRepository;
    private final CardRepository cardRepository;
    private final UserRepository userRepository;

    @Operation(summary = "관심 토글", description = "없으면 추가, 있으면 취소. isLiked=true/false 반환")
    @PostMapping("/{tradeId}/toggle")
    @Transactional
    public ReturnData<Map<String, Object>> toggle(
            @PathVariable String tradeId,
            @AuthenticationPrincipal String userId) {

        boolean exists = interestRepository.existsByUserIdAndTradeId(userId, tradeId);
        if (exists) {
            interestRepository.deleteByUserIdAndTradeId(userId, tradeId);
            return ReturnData.success(Map.of("isLiked", false));
        } else {
            interestRepository.save(PostInterest.builder()
                    .interestId(IdGenerator.generate())
                    .userId(userId)
                    .tradeId(tradeId)
                    .build());
            return ReturnData.success(Map.of("isLiked", true));
        }
    }

    @Operation(summary = "관심 여부 조회")
    @GetMapping("/{tradeId}/status")
    public ReturnData<Map<String, Object>> status(
            @PathVariable String tradeId,
            @AuthenticationPrincipal String userId) {

        boolean liked = interestRepository.existsByUserIdAndTradeId(userId, tradeId);
        return ReturnData.success(Map.of("isLiked", liked));
    }

    @Operation(summary = "내 관심 목록 조회", description = "판매글 + 카드 + 판매자 정보 포함")
    @GetMapping("/my")
    public ReturnData<List<Map<String, Object>>> myInterests(
            @AuthenticationPrincipal String userId) {

        List<PostInterest> interests = interestRepository.findByUserIdOrderByCreatedAtDesc(userId);
        List<String> tradeIds = interests.stream().map(PostInterest::getTradeId).toList();

        List<TradePost> trades = tradePostRepository.findAllById(tradeIds);
        Map<String, TradePost> tradeMap = trades.stream()
                .collect(Collectors.toMap(TradePost::getTradeId, Function.identity()));

        List<String> cardIds = trades.stream().map(TradePost::getCardId).distinct().toList();
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds).stream()
                .collect(Collectors.toMap(Card::getCardId, Function.identity()));

        List<String> sellerIds = trades.stream().map(TradePost::getSellerId).distinct().toList();
        Map<String, User> userMap = userRepository.findAllById(sellerIds).stream()
                .collect(Collectors.toMap(User::getUserId, Function.identity()));

        List<Map<String, Object>> result = interests.stream()
                .filter(i -> tradeMap.containsKey(i.getTradeId()))
                .map(i -> {
                    TradePost t = tradeMap.get(i.getTradeId());
                    Card card = cardMap.get(t.getCardId());
                    User seller = userMap.get(t.getSellerId());
                    return (Map<String, Object>) Map.of(
                            "tradeId", t.getTradeId(),
                            "title", t.getTitle(),
                            "price", t.getPrice() != null ? t.getPrice() : 0,
                            "status", t.getStatus(),
                            "cardStatus", t.getCardStatus(),
                            "imageUrl", t.getImageUrl() != null ? t.getImageUrl() : "",
                            "card", card != null ? Map.of(
                                    "cardId", card.getCardId(),
                                    "name", card.getName(),
                                    "rarityCode", card.getRarityCode() != null ? card.getRarityCode() : ""
                            ) : Map.of(),
                            "seller", seller != null ? Map.of(
                                    "nickname", seller.getNickname()
                            ) : Map.of(),
                            "likedAt", i.getCreatedAt().toString()
                    );
                })
                .toList();

        return ReturnData.success(result);
    }
}
