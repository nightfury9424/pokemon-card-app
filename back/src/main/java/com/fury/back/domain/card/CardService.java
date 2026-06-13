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
    /** 관리자 폼 카드 추가 — official_card_code/super/sub 보존 + is_visible=true 명시. INSERT만 커밋(시세/이미지는 enrich 분리). */
    Map<String, Object> addCardFromAdmin(AdminAddCardRequest request);
    /** 추가 직후 보강 — scrydex 이미지 다운로드 + KO 예상가 즉시 계산/저장. 실패해도 카드 자체엔 영향 없게 호출측 try-catch. */
    Map<String, Object> enrichCardAfterAdd(String cardId, String enScrydexRef, String jpScrydexRef);
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
    List<CardDto> getActiveOrderCards(int size);
    Map<String, Object> getPromoCards(String name, int page, int size);
    ReturnData<List<CardDto>> getCardsByProduct(String productId);
    ReturnData<List<CardDto>> getCardsByCollectionNumber(String collectionNumber, String language);
}
