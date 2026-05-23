package com.fury.back.domain.interest;

import com.fury.back.common.IdGenerator;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.Card;
import com.fury.back.domain.card.CardRepository;
import com.fury.back.storage.CardCdnUrls;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * 카드 단위 찜 API. 거래 리스트(카드 마켓)에서 하트 토글, MY > 관심 목록에서 list 조회.
 */
@Tag(name = "CardInterest", description = "카드 단위 관심 목록 API")
@RestController
@RequestMapping("/api/card-interests")
@RequiredArgsConstructor
public class CardInterestController {

    private final CardInterestRepository cardInterestRepository;
    private final CardRepository cardRepository;
    private final CardCdnUrls cardCdnUrls;

    @Operation(summary = "카드 찜 토글 — 없으면 추가, 있으면 취소. isLiked 반환")
    @PostMapping("/{cardId}/toggle")
    @Transactional
    public ReturnData<Map<String, Object>> toggle(
            @PathVariable String cardId,
            @AuthenticationPrincipal String userId) {

        boolean exists = cardInterestRepository.existsByUserIdAndCardId(userId, cardId);
        if (exists) {
            cardInterestRepository.deleteByUserIdAndCardId(userId, cardId);
            return ReturnData.success(Map.of("isLiked", false));
        }
        cardInterestRepository.save(CardInterest.builder()
                .interestId(IdGenerator.generate())
                .userId(userId)
                .cardId(cardId)
                .build());
        return ReturnData.success(Map.of("isLiked", true));
    }

    @Operation(summary = "카드 찜 여부 조회")
    @GetMapping("/{cardId}/status")
    public ReturnData<Map<String, Object>> status(
            @PathVariable String cardId,
            @AuthenticationPrincipal String userId) {
        boolean liked = cardInterestRepository.existsByUserIdAndCardId(userId, cardId);
        return ReturnData.success(Map.of("isLiked", liked));
    }

    @Operation(summary = "여러 카드의 찜 여부 batch 조회 — 거래 리스트 row 표시용")
    @GetMapping("/statuses")
    public ReturnData<Map<String, Boolean>> statuses(
            @RequestParam("cardIds") List<String> cardIds,
            @AuthenticationPrincipal String userId) {
        if (cardIds.isEmpty()) return ReturnData.success(Map.of());
        List<CardInterest> liked = cardInterestRepository.findByUserIdAndCardIdIn(userId, cardIds);
        Map<String, Boolean> result = new HashMap<>();
        for (String id : cardIds) result.put(id, false);
        for (CardInterest i : liked) result.put(i.getCardId(), true);
        return ReturnData.success(result);
    }

    @Operation(summary = "내 관심 카드 목록 — 카드 정보 포함")
    @GetMapping("/me")
    public ReturnData<List<Map<String, Object>>> myInterests(
            @AuthenticationPrincipal String userId) {

        List<CardInterest> interests = cardInterestRepository.findByUserIdOrderByCreatedAtDesc(userId);
        List<String> cardIds = interests.stream().map(CardInterest::getCardId).toList();
        Map<String, Card> cardMap = cardRepository.findAllById(cardIds).stream()
                .collect(Collectors.toMap(Card::getCardId, Function.identity()));

        List<Map<String, Object>> result = interests.stream()
                .map(i -> {
                    Card card = cardMap.get(i.getCardId());
                    Map<String, Object> m = new HashMap<>();
                    m.put("cardId", i.getCardId());
                    m.put("likedAt", i.getCreatedAt().toString());
                    if (card != null) {
                        m.put("name", card.getName());
                        m.put("rarityCode", card.getRarityCode());
                        // CardCdnUrls로 S3 CDN URL 직접 빌드 + jpScrydexRef/enScrydexRef 같이 내려서
                        // front resolveCardImageUrl이 로컬→CDN→scrydex 우선순위로 fallback 가능하게.
                        m.put("imageUrl", cardCdnUrls.forCard(card));
                        m.put("jpScrydexRef", card.getJpScrydexRef());
                        m.put("enScrydexRef", card.getEnScrydexRef());
                        m.put("language", card.getLanguage());
                    }
                    return m;
                })
                .toList();
        return ReturnData.success(result);
    }
}
