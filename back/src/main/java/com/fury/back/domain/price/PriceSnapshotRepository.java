package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface PriceSnapshotRepository extends JpaRepository<PriceSnapshot, String> {

    // 환율/계수 같은 SYSTEM 단일 키 최신 1건 (REFACTOR_2026-05-12.md 2-① 환율 DB 단일화)
    Optional<PriceSnapshot> findFirstByCardIdAndSourceOrderByTradedAtDesc(String cardId, String source);

    List<PriceSnapshot> findByCardIdOrderByTradedAtDesc(String cardId);

    List<PriceSnapshot> findByCardIdAndTradedAtAfterOrderByTradedAtDesc(String cardId, LocalDateTime after);

    List<PriceSnapshot> findByCardIdInAndCardStatusOrderByTradedAtDesc(List<String> cardIds, String cardStatus);

    // 해외 시세 복수 소스 (SCRYDEX_JP, SCRYDEX_EN 등)
    List<PriceSnapshot> findByCardIdAndSourceInAndCardStatusOrderByTradedAtDesc(
            String cardId, List<String> sources, String cardStatus);

    // 리스트용: 카드 목록의 화면 표시용 최신 가격 스냅샷을 소스별 1건씩 조회
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id, source) * FROM price_snapshots
            WHERE card_id IN (:cardIds)
              AND source IN ('SCRYDEX_EN', 'SCRYDEX_JP', 'KO_ESTIMATED')
              AND (source = 'KO_ESTIMATED' OR card_status = 'RAW')
            ORDER BY card_id, source, traded_at DESC
            """)
    List<PriceSnapshot> findLatestMarketSnapshotsByCardIds(@Param("cardIds") List<String> cardIds);

    // 계수 계산용: 국내 실거래만 (NAVER_CAFE + BUNJANG)
    @Query("SELECT ps FROM PriceSnapshot ps WHERE ps.cardId IN :cardIds AND ps.source IN ('NAVER_CAFE', 'BUNJANG') AND ps.cardStatus = 'RAW' AND ps.tradedAt > :after")
    List<PriceSnapshot> findKoreanPrices(
            @Param("cardIds") List<String> cardIds,
            @Param("after") LocalDateTime after);

    // 계수 계산용: 특정 소스 글로벌 스냅샷 (RAW만, GRADED 제외)
    @Query("SELECT ps FROM PriceSnapshot ps WHERE ps.cardId IN :cardIds AND ps.source = :source AND ps.cardStatus = 'RAW' AND ps.tradedAt > :after")
    List<PriceSnapshot> findGlobalPrices(
            @Param("cardIds") List<String> cardIds,
            @Param("source") String source,
            @Param("after") LocalDateTime after);

    // 리스트용: 카드 목록의 SCRYDEX_EN 최신 가격 (1장씩)
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'SCRYDEX_EN' AND card_status = 'RAW'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findLatestScrydexEnByCardIds(@Param("cardIds") List<String> cardIds);

    // 중복 저장 방지: 같은 날 같은 카드/소스의 스냅샷 존재 여부
    boolean existsByCardIdAndSourceAndTradedAtAfter(String cardId, String source, LocalDateTime after);

    // 시장 계수 히스토리 (card_id='ko_market_coefficient', source='SYSTEM')
    List<PriceSnapshot> findByCardIdAndSourceOrderByTradedAtAsc(String cardId, String source);

    // 리스트용: 카드 목록의 SCRYDEX_JP 최신 가격 (EN 없는 카드 폴백)
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'SCRYDEX_JP' AND card_status = 'RAW'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findLatestScrydexJpByCardIds(@Param("cardIds") List<String> cardIds);

    // 프로모 전용: RAW 없는 카드 PSA10 최신가 fallback
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'SCRYDEX_JP'
              AND card_status = 'GRADED' AND grading_company = 'PSA' AND grade_value = '10'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findLatestScrydexJpPsa10ByCardIds(@Param("cardIds") List<String> cardIds);

    // EN PSA10 최신가 — GRADED 자산 displayPrice 계산용
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'SCRYDEX_EN'
              AND card_status = 'GRADED' AND grading_company = 'PSA' AND grade_value = '10'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findLatestScrydexEnPsa10ByCardIds(@Param("cardIds") List<String> cardIds);

    // KO 예상가 리스트용: 카드 목록의 최신 KO_ESTIMATED 1건씩
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'KO_ESTIMATED'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findLatestKoEstimatedByCardIds(@Param("cardIds") List<String> cardIds);

    // 자산 등록 시점 기준가 조회 — 단건 카드 최신 KO_ESTIMATED
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id = :cardId AND source = 'KO_ESTIMATED'
            ORDER BY traded_at DESC LIMIT 1
            """)
    java.util.Optional<PriceSnapshot> findLatestKoEstimatedByCardId(@Param("cardId") String cardId);

    // KO 예상가 히스토리 (카드 상세 차트용)
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id = :cardId AND source = 'KO_ESTIMATED'
            AND traded_at > :after
            ORDER BY traded_at ASC
            """)
    List<PriceSnapshot> findKoEstimatedHistory(
            @Param("cardId") String cardId,
            @Param("after") LocalDateTime after);

    // NAVER_CAFE 낙찰가 (최근 30일, RAW만) — KO 실거래가 산출용
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id = :cardId AND source = 'NAVER_CAFE' AND card_status = 'RAW'
            AND traded_at > :after
            ORDER BY traded_at DESC
            """)
    List<PriceSnapshot> findRecentNaverCafeRaw(
            @Param("cardId") String cardId,
            @Param("after") LocalDateTime after);

    // NAVER_CAFE 낙찰가 — 카드 목록용 (전체, 150일 이내)
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'NAVER_CAFE' AND card_status = 'RAW'
            AND traded_at > :after
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findRecentNaverCafeRawByCardIds(
            @Param("cardIds") List<String> cardIds,
            @Param("after") LocalDateTime after);

    // 레어도별 계수 전체 (ko_coef_{rarity}, 최신값)
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE card_id LIKE 'ko_coef_%' AND source = 'SYSTEM'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findAllRarityCoefficients();

    // CARD-level 계수 (ko_price_coefficients 활성). [card_id, coef_type, coef]
    @Query(nativeQuery = true, value = """
            SELECT card_id, coef_type, coef
            FROM ko_price_coefficients
            WHERE scope = 'CARD' AND active = true
            """)
    List<Object[]> findActiveCardCoefficients();

    // 국내 실거래 단건 조회 (NAVER_CAFE + BUNJANG)
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id = :cardId
              AND source IN ('NAVER_CAFE', 'BUNJANG')
              AND card_status = 'RAW'
              AND traded_at > :after
            ORDER BY traded_at DESC
            """)
    List<PriceSnapshot> findDomesticRaw(
            @Param("cardId") String cardId,
            @Param("after") LocalDateTime after);

    // 국내 실거래 목록 조회 (리스트용, 180일 이내 — NAVER_CAFE + BUNJANG)
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id IN (:cardIds)
              AND source IN ('NAVER_CAFE', 'BUNJANG')
              AND card_status = 'RAW'
              AND traded_at > :after
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findDomesticRawByCardIds(
            @Param("cardIds") List<String> cardIds,
            @Param("after") LocalDateTime after);

    // 단일 카드 단일 소스 히스토리 (차트용, 시간 오름차순)
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id = :cardId AND source = :source AND card_status = 'RAW'
              AND traded_at > :after
            ORDER BY traded_at ASC
            """)
    List<PriceSnapshot> findByCardIdAndSourceAndTradedAtAfterOrderByTradedAtAsc(
            @Param("cardId") String cardId,
            @Param("source") String source,
            @Param("after") LocalDateTime after);

    List<PriceSnapshot> findBySourceAndTradedAtBetweenOrderByTradedAtAsc(
            String source, LocalDateTime start, LocalDateTime end);

    // PSA 등급별 히스토리 (scrydex 배치 저장분, 차트용)
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id = :cardId AND source = :source
              AND card_status = 'GRADED' AND grading_company = 'PSA' AND grade_value = :gradeValue
              AND traded_at > :after
            ORDER BY traded_at ASC
            """)
    List<PriceSnapshot> findScrydexPsaHistory(
            @Param("cardId") String cardId,
            @Param("source") String source,
            @Param("gradeValue") String gradeValue,
            @Param("after") LocalDateTime after);

    // KO_ESTIMATED 일괄 삭제 (재계산 시 기존 행 제거)
    void deleteByCardIdInAndSource(List<String> cardIds, String source);

    // KO_ESTIMATED 오늘자만 삭제 (히스토리 보존 upsert)
    @Modifying
    @Query(nativeQuery = true, value = """
            DELETE FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'KO_ESTIMATED'
            AND DATE(traded_at) = CURRENT_DATE
            """)
    void deleteTodayKoEstimated(@Param("cardIds") List<String> cardIds);

    // KO_ESTIMATED 특정 날짜 범위 삭제 (Turn C-2 backfill force 모드용. FK CASCADE로 audit도 삭제)
    @Modifying
    @Query(nativeQuery = true, value = """
            DELETE FROM price_snapshots
            WHERE card_id IN (:cardIds) AND source = 'KO_ESTIMATED'
            AND traded_at >= :start AND traded_at < :end
            """)
    void deleteKoEstimatedByDateRange(
            @Param("cardIds") List<String> cardIds,
            @Param("start") LocalDateTime start,
            @Param("end") LocalDateTime end);

    // KREAM source의 특정 등급(PSA10/PSA9 등) **일별** 시계열 — KO 차트 psa10Line/psa9Line 채움용.
    // 같은 날 여러 row 들어와도 일별 평균 1포인트로 합쳐서 반환.
    @Query(nativeQuery = true, value = """
            SELECT TO_CHAR(traded_at, 'YYYY-MM-DD') AS d, AVG(price)::bigint AS price
            FROM price_snapshots
            WHERE card_id = :cardId AND source = 'KREAM'
              AND grading_company = :company AND grade_value = :grade
              AND traded_at > :after
            GROUP BY TO_CHAR(traded_at, 'YYYY-MM-DD')
            ORDER BY TO_CHAR(traded_at, 'YYYY-MM-DD') ASC
            """)
    List<Object[]> findKreamGradedSeries(
            @Param("cardId") String cardId,
            @Param("company") String company,
            @Param("grade") String grade,
            @Param("after") LocalDateTime after);

    // KREAM source의 Ungraded(RAW) **일별** 시계열 — KO 차트 line 채움용.
    // findKreamGradedSeries와 동일 패턴, 등급 NULL만 차이.
    @Query(nativeQuery = true, value = """
            SELECT TO_CHAR(traded_at, 'YYYY-MM-DD') AS d, AVG(price)::bigint AS price
            FROM price_snapshots
            WHERE card_id = :cardId AND source = 'KREAM' AND card_status = 'RAW'
              AND traded_at > :after
            GROUP BY TO_CHAR(traded_at, 'YYYY-MM-DD')
            ORDER BY TO_CHAR(traded_at, 'YYYY-MM-DD') ASC
            """)
    List<Object[]> findKreamRawSeries(
            @Param("cardId") String cardId,
            @Param("after") LocalDateTime after);

    // KREAM 기반 KO 독점 프로모 카드의 최신 Ungraded(RAW) 체결가
    // — refreshKoEstimatesFromSnapshots() 의 프로모 branch 에서 KO_ESTIMATED 대표값으로 사용.
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (ps.card_id) ps.card_id, ps.price
            FROM price_snapshots ps
            JOIN cards c ON c.card_id = ps.card_id
            WHERE ps.source = 'KREAM' AND ps.card_status = 'RAW'
              AND (c.en_scrydex_ref IS NULL OR c.en_scrydex_ref LIKE 'NO\\_%' ESCAPE '\\')
              AND (c.jp_scrydex_ref IS NULL OR c.jp_scrydex_ref LIKE 'NO\\_%' ESCAPE '\\')
            ORDER BY ps.card_id, ps.traded_at DESC
            """)
    List<Object[]> findLatestKreamRawForKoExclusivePromos();

    // SCRYDEX_EN 전체 최신 (KO_ESTIMATED 일괄 생성 소스)
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE source = 'SCRYDEX_EN' AND card_status = 'RAW'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findAllLatestScrydexEn();

    // SCRYDEX_JP 전체 최신 (EN 없는 카드 배치 폴백)
    @Query(nativeQuery = true, value = """
            SELECT DISTINCT ON (card_id) * FROM price_snapshots
            WHERE source = 'SCRYDEX_JP' AND card_status = 'RAW'
            ORDER BY card_id, traded_at DESC
            """)
    List<PriceSnapshot> findAllLatestScrydexJp();

    // 시장 보정 계수 (ko_adjustment_factor) 최신 조회
    @Query(nativeQuery = true, value = """
            SELECT * FROM price_snapshots
            WHERE card_id = 'ko_adjustment_factor' AND source = 'SYSTEM'
            ORDER BY traded_at DESC LIMIT 1
            """)
    List<PriceSnapshot> findLatestMarketAdjustment();

    // ko_coef_* 최신 행 전체 비율 업데이트
    @Modifying
    @Query(nativeQuery = true, value = """
            UPDATE price_snapshots
            SET price = ROUND(price * :ratio)
            WHERE source = 'SYSTEM'
              AND card_id LIKE 'ko_coef_%'
              AND traded_at = (
                SELECT MAX(ps2.traded_at) FROM price_snapshots ps2
                WHERE ps2.card_id = price_snapshots.card_id AND ps2.source = 'SYSTEM'
              )
            """)
    void applyAdjustmentRatioToCoefficients(@Param("ratio") double ratio);
}
