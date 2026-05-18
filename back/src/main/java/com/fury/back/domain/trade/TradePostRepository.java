package com.fury.back.domain.trade;

import com.fury.back.domain.trade.dto.HogaLevelDto;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface TradePostRepository extends JpaRepository<TradePost, String> {

    Page<TradePost> findByStatusOrderByCreatedAtDesc(String status, Pageable pageable);

    Page<TradePost> findBySellerIdOrderByCreatedAtDesc(String sellerId, Pageable pageable);

    @Query("SELECT t FROM TradePost t WHERE t.status = 'OPEN' AND " +
           "(:cardId IS NULL OR t.cardId = :cardId) " +
           "ORDER BY t.createdAt DESC")
    Page<TradePost> findOpenByCardId(@Param("cardId") String cardId, Pageable pageable);

    List<TradePost> findBySellerIdAndStatus(String sellerId, String status);

    List<TradePost> findByAssetIdOrderByCreatedAtDesc(String assetId);

    List<TradePost> findByAssetIdAndStatus(String assetId, String status);

    List<TradePost> findByAssetIdAndStatusIn(String assetId, List<String> statuses);

    boolean existsByAssetIdAndStatusIn(String assetId, List<String> statuses);

    // 카드별 그룹 요약: cardId, 판매 수, 평균가, 최저가
    @Query("SELECT t.cardId, COUNT(t), AVG(t.price), MIN(t.price) " +
           "FROM TradePost t WHERE t.status = 'OPEN' AND t.price IS NOT NULL " +
           "GROUP BY t.cardId ORDER BY COUNT(t) DESC")
    List<Object[]> findCardTradeSummary(Pageable pageable);

    /**
     * 호가창 매도 group-by. 같은 cardStatus + grading 필터 + 동일 가격끼리 묶어 count.
     *
     * <p>{@code gradingCompany}/{@code gradeValue}가 null이면 해당 필터 무시 (RAW 케이스).
     */
    @Query("""
            SELECT new com.fury.back.domain.trade.dto.HogaLevelDto(t.price, COUNT(t))
            FROM TradePost t
            WHERE t.cardId = :cardId
              AND t.status = 'OPEN'
              AND t.price IS NOT NULL
              AND t.cardStatus = :cardStatus
              AND ((:gradingCompany IS NULL) OR t.gradingCompany = :gradingCompany)
              AND ((:gradeValue IS NULL) OR t.gradeValue = :gradeValue)
            GROUP BY t.price
            ORDER BY t.price DESC
            """)
    List<HogaLevelDto> findHogaLevels(
            @Param("cardId") String cardId,
            @Param("cardStatus") String cardStatus,
            @Param("gradingCompany") String gradingCompany,
            @Param("gradeValue") String gradeValue);

    /**
     * 특정 가격의 활성 매도 호가 (하단 시트 등록자 리스트용). 등록일 오래된 순.
     */
    @Query("""
            SELECT t FROM TradePost t
            WHERE t.cardId = :cardId
              AND t.status = 'OPEN'
              AND t.cardStatus = :cardStatus
              AND t.price = :price
              AND ((:gradingCompany IS NULL) OR t.gradingCompany = :gradingCompany)
              AND ((:gradeValue IS NULL) OR t.gradeValue = :gradeValue)
            ORDER BY t.createdAt ASC
            """)
    List<TradePost> findHogaListings(
            @Param("cardId") String cardId,
            @Param("cardStatus") String cardStatus,
            @Param("gradingCompany") String gradingCompany,
            @Param("gradeValue") String gradeValue,
            @Param("price") Integer price);
}
