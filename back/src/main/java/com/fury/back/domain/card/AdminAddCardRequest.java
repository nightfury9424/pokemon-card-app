package com.fury.back.domain.card;

/**
 * 관리자 페이지(AdminController) 카드 추가 폼 전용 요청.
 * <p>AddCardRequest(외부/프로모 자동결정)와 달리, KO 카드의 official_card_code / super_type / sub_type 를
 * 폼에서 명시 입력받아 그대로 보존한다(=라우팅으로 CardServiceImpl.addCard 쓰면 koCardCode→official 손실).
 * card_type 컬럼은 어디서도 읽지 않는 드리프트라 의도적으로 제외(JPA 빌더 매핑 없음).
 *
 * @param type             KO | EN | JP (→ language)
 * @param officialCardCode KO 공식 카드코드 (pokemoncard.co.kr). KO 카드일 때 채움.
 */
public record AdminAddCardRequest(
        String type,
        String name,
        String productId,
        String rarityCode,
        String collectionNumber,
        String superType,
        String subType,
        String officialCardCode,
        String enScrydexRef,
        String jpScrydexRef
) {
}
