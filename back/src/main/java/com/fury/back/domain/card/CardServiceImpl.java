package com.fury.back.domain.card;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.dto.CardDto;
import com.fury.back.domain.card.dto.CardSearchDto;
import com.fury.back.domain.price.PriceSnapshot;
import com.fury.back.domain.price.PriceSnapshotRepository;
import com.fury.back.domain.product.ProductRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.Optional;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class CardServiceImpl implements CardService {

    private final CardRepository cardRepository;
    private final ProductRepository productRepository;
    private final PriceSnapshotRepository priceSnapshotRepository;

    @Override
    public ReturnData<CardDto> getCard(String cardId) {
        if (cardId == null || cardId.isBlank()) {
            return ReturnData.badRequest("cardId는 필수입니다.");
        }
        Optional<Card> card = cardRepository.findById(cardId);
        return card.<ReturnData<CardDto>>map(c -> {
            var product = productRepository.findById(c.getProductId()).orElse(null);
            return ReturnData.success(CardDto.from(c, product));
        }).orElseGet(() -> ReturnData.notFound("카드를 찾을 수 없습니다. cardId=" + cardId));
    }

    @Override
    public ReturnData<List<CardSearchDto>> searchCards(String name) {
        if (name == null || name.isBlank()) {
            return ReturnData.badRequest("name은 필수입니다.");
        }
        List<CardSearchDto> result = cardRepository.findByNameContainingIgnoreCase(name)
                .stream()
                .map(CardSearchDto::from)
                .toList();
        return ReturnData.success(result);
    }

    @Override
    public ReturnData<CardDto> getCardByCode(String officialCardCode) {
        if (officialCardCode == null || officialCardCode.isBlank()) {
            return ReturnData.badRequest("officialCardCode는 필수입니다.");
        }
        Optional<Card> card = cardRepository.findByOfficialCardCode(officialCardCode);
        return card.<ReturnData<CardDto>>map(c -> ReturnData.success(CardDto.from(c)))
                .orElseGet(() -> ReturnData.notFound("카드를 찾을 수 없습니다. code=" + officialCardCode));
    }

    @Override
    public Map<String, Object> getCardsByRarity(List<String> rarityCodes, Pageable pageable) {
        Page<Card> page = cardRepository.findByRarityCodeInAndLanguageOrderByNameAsc(rarityCodes, "KO", pageable);
        return buildMarketResult(page);
    }

    @Override
    public Map<String, Object> searchCardsByNameAndRarity(String name, List<String> rarityCodes, Pageable pageable) {
        Page<Card> page = cardRepository.findByNameContainingIgnoreCaseAndRarityCodeInAndLanguageOrderByNameAsc(
                name, rarityCodes, "KO", pageable);
        return buildMarketResult(page);
    }

    private Map<String, Object> buildMarketResult(Page<Card> page) {
        var cardIds = page.getContent().stream().map(Card::getCardId).toList();
        // 카드별 최신 RAW 거래가 한번에 조회 (N+1 방지)
        Map<String, PriceSnapshot> latestPriceMap = priceSnapshotRepository
                .findByCardIdInAndCardStatusOrderByTradedAtDesc(cardIds, "RAW")
                .stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));
        return Map.of(
                "content", page.getContent().stream()
                        .map(c -> CardDto.fromWithPrice(c, latestPriceMap.get(c.getCardId())))
                        .toList(),
                "totalElements", page.getTotalElements(),
                "totalPages", page.getTotalPages(),
                "page", page.getNumber()
        );
    }

    @Override
    public Map<String, Object> getCardsByRarityOrderByPrice(List<String> rarityCodes, String name, int size, int offset) {
        List<Card> cards = cardRepository.findByRarityOrderByLatestPriceDesc(rarityCodes, name, size, offset);
        long total = cardRepository.countByRarityAndName(rarityCodes, name);
        var cardIds = cards.stream().map(Card::getCardId).toList();
        Map<String, PriceSnapshot> latestPriceMap = priceSnapshotRepository
                .findByCardIdInAndCardStatusOrderByTradedAtDesc(cardIds, "RAW")
                .stream()
                .collect(Collectors.toMap(PriceSnapshot::getCardId, s -> s, (a, b) -> a));
        return Map.of(
                "content", cards.stream()
                        .map(c -> CardDto.fromWithPrice(c, latestPriceMap.get(c.getCardId())))
                        .toList(),
                "totalElements", total,
                "totalPages", (int) Math.ceil((double) total / size),
                "page", offset / size
        );
    }

    @Override
    public ReturnData<List<CardDto>> getCardsByProduct(String productId) {
        if (productId == null || productId.isBlank()) {
            return ReturnData.badRequest("productId는 필수입니다.");
        }
        List<CardDto> cards = cardRepository.findByProductId(productId)
                .stream()
                .map(CardDto::from)
                .toList();
        return ReturnData.success(cards);
    }

    @Override
    public ReturnData<List<CardDto>> getCardsByCollectionNumber(String collectionNumber, String language) {
        List<Card> cards = cardRepository.findByCollectionNumberAndLanguage(collectionNumber, language);
        if (cards.isEmpty()) {
            return ReturnData.notFound("카드를 찾을 수 없습니다. number=" + collectionNumber);
        }
        return ReturnData.success(cards.stream().map(CardDto::from).toList());
    }

    @Override
    public ReturnData<CardDto> registerScanResult(ParameterData parameterData) {
        String officialCardCode = parameterData.getString("officialCardCode");
        if (officialCardCode == null || officialCardCode.isBlank()) {
            return ReturnData.badRequest("officialCardCode는 필수입니다.");
        }
        Optional<Card> card = cardRepository.findByOfficialCardCode(officialCardCode);
        return card.<ReturnData<CardDto>>map(c -> ReturnData.success(CardDto.from(c)))
                .orElseGet(() -> ReturnData.notFound("스캔된 카드를 DB에서 찾을 수 없습니다. code=" + officialCardCode));
    }
}
