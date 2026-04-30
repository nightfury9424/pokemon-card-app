package com.fury.back.domain.card;

import com.fury.back.common.ParameterData;
import com.fury.back.common.ReturnData;
import com.fury.back.domain.card.dto.CardDto;
import com.fury.back.domain.card.dto.CardSearchDto;
import org.springframework.data.domain.Pageable;

import java.util.List;
import java.util.Map;

public interface CardService {
    ReturnData<CardDto> getCard(String cardId);
    ReturnData<List<CardSearchDto>> searchCards(String name);
    ReturnData<CardDto> getCardByCode(String officialCardCode);
    ReturnData<CardDto> registerScanResult(ParameterData parameterData);
    Map<String, Object> getCardsByRarity(List<String> rarityCodes, Pageable pageable);
    Map<String, Object> searchCardsByNameAndRarity(String name, List<String> rarityCodes, Pageable pageable);
    Map<String, Object> getCardsByRarityOrderByPrice(List<String> rarityCodes, String name, int size, int offset);
    ReturnData<List<CardDto>> getCardsByProduct(String productId);
    ReturnData<List<CardDto>> getCardsByCollectionNumber(String collectionNumber, String language);
}
