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
    ReturnData<CardDto> getCardWithPrice(String cardId);
    Map<String, Object> addCard(AddCardRequest request);
    ReturnData<List<CardSearchDto>> searchCards(String name);
    ReturnData<List<CardSearchDto>> searchCards(String name, String language);
    ReturnData<CardDto> getCardByCode(String officialCardCode);
    ReturnData<CardDto> registerScanResult(ParameterData parameterData);
    Map<String, Object> getCardsByRarity(List<String> rarityCodes, Pageable pageable);
    Map<String, Object> searchCardsByNameAndRarity(String name, List<String> rarityCodes, Pageable pageable);
    Map<String, Object> getCardsByRarityOrderByPrice(List<String> rarityCodes, String name, int size, int offset);
    Map<String, Object> getMarketCards(List<String> rarityCodes, String name, int page, int size, String sortBy, String sortDir);
    List<CardDto> getTopGainerCards(int size);
    List<CardDto> getTopLoserCards(int size);
    List<CardDto> getRecentGainerCards(int days, int size);
    List<CardDto> getRecentLoserCards(int days, int size);
    List<CardDto> getPopularCards(int size);
    Map<String, Object> getPromoCards(String name, int page, int size);
    ReturnData<List<CardDto>> getCardsByProduct(String productId);
    ReturnData<List<CardDto>> getCardsByCollectionNumber(String collectionNumber, String language);
}
