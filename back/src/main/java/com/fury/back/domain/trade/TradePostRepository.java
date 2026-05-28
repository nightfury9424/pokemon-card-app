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

    /** 거래 목록 default — OPEN+RESERVED active 상태만 (COMPLETED/DELETED 제외). */
    Page<TradePost> findByStatusInOrderByCreatedAtDesc(List<String> statuses, Pageable pageable);

    Page<TradePost> findBySellerIdOrderByCreatedAtDesc(String sellerId, Pageable pageable);

    /** 내 판매 항목 default — sellerId + active(OPEN+RESERVED)만. DELETED/COMPLETED 숨김. */
    Page<TradePost> findBySellerIdAndStatusInOrderByCreatedAtDesc(
            String sellerId, List<String> statuses, Pageable pageable);

    /** 카드별 active 거래 — RESERVED도 호가/거래 탭에 보임. */
    @Query("SELECT t FROM TradePost t WHERE t.status IN ('OPEN', 'RESERVED') AND " +
           "(:cardId IS NULL OR t.cardId = :cardId) " +
           "ORDER BY t.createdAt DESC")
    Page<TradePost> findOpenByCardId(@Param("cardId") String cardId, Pageable pageable);

    List<TradePost> findBySellerIdAndStatus(String sellerId, String status);

    /** 계정 탈퇴 시 OPEN/RESERVED 일괄 처리용 (paged X). */
    List<TradePost> findBySellerIdAndStatusIn(String sellerId, List<String> statuses);

    /** 카드 상세 "대기 중인 주문" — 내 판매글을 카드별 필터 (Phase 1). */
    Page<TradePost> findBySellerIdAndCardIdAndStatusOrderByCreatedAtDesc(
            String sellerId, String cardId, String status, Pageable pageable);

    /** sellerId + cardId 단순 매칭 (status 무시 — 디버깅/내림차순). */
    Page<TradePost> findBySellerIdAndCardIdOrderByCreatedAtDesc(
            String sellerId, String cardId, Pageable pageable);

    @Query("""
            SELECT t FROM TradePost t
            WHERE (:sellerId IS NULL OR t.sellerId = :sellerId)
              AND (:cardId IS NULL OR t.cardId = :cardId)
              AND t.status IN :statuses
              AND t.sellerId NOT IN :excludedSellerIds
            ORDER BY t.createdAt DESC
            """)
    Page<TradePost> findFilteredExcludingSellers(
            @Param("sellerId") String sellerId,
            @Param("cardId") String cardId,
            @Param("statuses") List<String> statuses,
            @Param("excludedSellerIds") List<String> excludedSellerIds,
            Pageable pageable);

    /** 호가창 MY badge — 내가 등록한 active ASK 가격 set (OPEN+RESERVED 포함). */
    @Query("""
            SELECT DISTINCT t.price FROM TradePost t
            WHERE t.sellerId = :sellerId
              AND t.cardId = :cardId
              AND t.status IN ('OPEN', 'RESERVED')
              AND t.price IS NOT NULL
              AND t.cardStatus = :cardStatus
              AND ((:gradingCompany IS NULL) OR t.gradingCompany = :gradingCompany)
              AND ((:gradeValue IS NULL) OR t.gradeValue = :gradeValue)
            """)
    List<Integer> findMyOpenAskPrices(
            @Param("sellerId") String sellerId,
            @Param("cardId") String cardId,
            @Param("cardStatus") String cardStatus,
            @Param("gradingCompany") String gradingCompany,
            @Param("gradeValue") String gradeValue);

    List<TradePost> findByAssetIdOrderByCreatedAtDesc(String assetId);

    List<TradePost> findByAssetIdAndStatus(String assetId, String status);

    List<TradePost> findByAssetIdAndStatusIn(String assetId, List<String> statuses);

    boolean existsByAssetIdAndStatusIn(String assetId, List<String> statuses);

    // 카드별 그룹 요약: cardId, 판매 수, 평균가, 최저가 (OPEN+RESERVED 포함 — RESERVED도 active).
    @Query("SELECT t.cardId, COUNT(t), AVG(t.price), MIN(t.price) " +
           "FROM TradePost t WHERE t.status IN ('OPEN', 'RESERVED') AND t.price IS NOT NULL " +
           "GROUP BY t.cardId ORDER BY COUNT(t) DESC")
    List<Object[]> findCardTradeSummary(Pageable pageable);

    /**
     * 호가창 매도 group-by. 같은 cardStatus + grading 필터 + 동일 가격끼리 묶어 count.
     *
     * <p><b>중요</b>: 호가창은 TradePost를 가격별로 묶어 보여주는 read view다.
     * 별도 Hoga/Orderbook entity를 만들지 말 것. 새 글 객체 도입 금지.
     *
     * <p>{@code gradingCompany}/{@code gradeValue}가 null이면 해당 필터 무시 (RAW 케이스).
     */
    @Query("""
            SELECT new com.fury.back.domain.trade.dto.HogaLevelDto(t.price, COUNT(t))
            FROM TradePost t
            WHERE t.cardId = :cardId
              AND t.status IN ('OPEN', 'RESERVED')
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
              AND t.status IN ('OPEN', 'RESERVED')
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
