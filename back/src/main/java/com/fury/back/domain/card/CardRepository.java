package com.fury.back.domain.card;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface CardRepository extends JpaRepository<Card, String> {
    List<Card> findByProductId(String productId);

    List<Card> findByNameContainingIgnoreCase(String name);

    List<Card> findByLanguage(String language);

    List<Card> findBySuperType(String superType);

    java.util.Optional<Card> findByOfficialCardCode(String officialCardCode);

    org.springframework.data.domain.Page<Card> findByRarityCodeInAndLanguageOrderByNameAsc(
            List<String> rarityCodes, String language, org.springframework.data.domain.Pageable pageable);

    org.springframework.data.domain.Page<Card> findByNameContainingIgnoreCaseAndRarityCodeInAndLanguageOrderByNameAsc(
            String name, List<String> rarityCodes, String language, org.springframework.data.domain.Pageable pageable);

    // EN scrydex 매핑 안 된 고레어 KO 카드
    List<Card> findByRarityCodeInAndLanguageAndEnScrydexRefIsNull(
            List<String> rarityCodes, String language);

    // EN scrydex 매핑 완료된 고레어 KO 카드
    List<Card> findByRarityCodeInAndLanguageAndEnScrydexRefIsNotNull(
            List<String> rarityCodes, String language);

    // 특정 제품의 고레어 카드 (세트 매핑용)
    List<Card> findByProductIdInAndRarityCodeInAndLanguage(
            List<String> productIds, List<String> rarityCodes, String language);

    // 최신 RAW 거래가 기준 내림차순 정렬
    @Query(nativeQuery = true, value = """
            SELECT c.* FROM cards c
            LEFT JOIN LATERAL (
                SELECT price FROM price_snapshots
                WHERE card_id = c.card_id AND card_status = 'RAW'
                ORDER BY traded_at DESC LIMIT 1
            ) ps ON true
            WHERE c.language = 'KO'
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY COALESCE(ps.price, 0) DESC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByLatestPriceDesc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    @Query(nativeQuery = true, value = """
            SELECT COUNT(*) FROM cards
            WHERE language = 'KO'
            AND rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(name) LIKE LOWER(CONCAT('%', :name, '%')))
            """)
    long countByRarityAndName(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name);
}
