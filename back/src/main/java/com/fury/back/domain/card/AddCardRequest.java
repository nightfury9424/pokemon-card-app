package com.fury.back.domain.card;

/**
 * 카드 수동 추가 요청.
 * - koCardCode: pokemoncard.co.kr 카드 코드 (BS2023001211 등). KO 카드가 있을 때만.
 * - productId: KO 카드가 있으면 세트 product_id, 없으면 null (자동으로 FOREIGN_ONLY 등 센티넬 사용)
 * - enScrydexRef / jpScrydexRef: 있는 것만 넘기면 됨. 둘 다 없어도 되고 하나만 있어도 됨.
 * - name: KO명 우선, 없으면 JP명이나 EN명
 */
public record AddCardRequest(
        String name,
        String rarityCode,
        String productId,       // optional — null이면 센티넬 자동 결정
        String collectionNumber,// optional
        String language,        // optional — null이면 자동 결정 (KO/JP/EN/MULTI)
        String enScrydexRef,    // optional
        String jpScrydexRef,    // optional
        String koCardCode       // optional — pokemoncard.co.kr 코드
) {
}
