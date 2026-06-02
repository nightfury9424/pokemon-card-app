package com.fury.back.domain.card;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface CardRepository extends JpaRepository<Card, String> {
    List<Card> findByProductId(String productId);

    List<Card> findByNameContainingIgnoreCase(String name);

    List<Card> findByNameContainingIgnoreCaseAndLanguage(String name, String language);

    List<Card> findByLanguage(String language);

    List<Card> findBySuperType(String superType);

    java.util.Optional<Card> findByOfficialCardCode(String officialCardCode);

    org.springframework.data.domain.Page<Card> findByRarityCodeInAndLanguageOrderByNameAsc(
            List<String> rarityCodes, String language, org.springframework.data.domain.Pageable pageable);

    org.springframework.data.domain.Page<Card> findByNameContainingIgnoreCaseAndRarityCodeInAndLanguageOrderByNameAsc(
            String name, List<String> rarityCodes, String language, org.springframework.data.domain.Pageable pageable);

    // 고레어 KO 카드 전체 (세트 무관)
    List<Card> findByRarityCodeInAndLanguage(List<String> rarityCodes, String language);

    // EN scrydex 매핑 안 된 고레어 KO 카드
    List<Card> findByRarityCodeInAndLanguageAndEnScrydexRefIsNull(
            List<String> rarityCodes, String language);

    // EN scrydex 매핑 완료된 고레어 KO 카드
    List<Card> findByRarityCodeInAndLanguageAndEnScrydexRefIsNotNull(
            List<String> rarityCodes, String language);

    // 특정 제품의 고레어 카드 (세트 매핑용)
    List<Card> findByProductIdInAndRarityCodeInAndLanguage(
            List<String> productIds, List<String> rarityCodes, String language);

    // 가격 내림차순
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            LEFT JOIN LATERAL (
                SELECT price AS ko_price
                FROM price_snapshots
                WHERE card_id = c.card_id AND source = 'KO_ESTIMATED'
                ORDER BY traded_at DESC LIMIT 1
            ) ko ON true
            LEFT JOIN LATERAL (
                SELECT COALESCE(
                  (SELECT price FROM price_snapshots WHERE card_id = c.card_id AND source = 'SCRYDEX_JP' AND card_status = 'RAW' ORDER BY traded_at DESC LIMIT 1),
                  CASE WHEN c.is_promo_exclusive THEN (SELECT price FROM price_snapshots WHERE card_id = c.card_id AND source = 'SCRYDEX_JP' ORDER BY traded_at DESC, price ASC LIMIT 1) END
                ) AS jp_price
            ) jp ON true
            LEFT JOIN LATERAL (
                SELECT price AS en_price
                FROM price_snapshots
                WHERE card_id = c.card_id AND source = 'SCRYDEX_EN' AND card_status = 'RAW'
                ORDER BY traded_at DESC LIMIT 1
            ) en ON true
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY
                CASE WHEN c.is_promo_exclusive THEN COALESCE(jp.jp_price, en.en_price)
                     ELSE ko.ko_price
                END DESC NULLS LAST, c.name ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByLatestPriceDesc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    // 가격 오름차순
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            LEFT JOIN LATERAL (
                SELECT price AS ko_price
                FROM price_snapshots
                WHERE card_id = c.card_id AND source = 'KO_ESTIMATED'
                ORDER BY traded_at DESC LIMIT 1
            ) ko ON true
            LEFT JOIN LATERAL (
                SELECT COALESCE(
                  (SELECT price FROM price_snapshots WHERE card_id = c.card_id AND source = 'SCRYDEX_JP' AND card_status = 'RAW' ORDER BY traded_at DESC LIMIT 1),
                  CASE WHEN c.is_promo_exclusive THEN (SELECT price FROM price_snapshots WHERE card_id = c.card_id AND source = 'SCRYDEX_JP' ORDER BY traded_at DESC, price ASC LIMIT 1) END
                ) AS jp_price
            ) jp ON true
            LEFT JOIN LATERAL (
                SELECT price AS en_price
                FROM price_snapshots
                WHERE card_id = c.card_id AND source = 'SCRYDEX_EN' AND card_status = 'RAW'
                ORDER BY traded_at DESC LIMIT 1
            ) en ON true
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY
                CASE WHEN c.is_promo_exclusive THEN COALESCE(jp.jp_price, en.en_price)
                     ELSE ko.ko_price
                END ASC NULLS LAST, c.name ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByLatestPriceAsc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    // 등급 내림차순 (높은 등급 → 낮은 등급)
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            -- 한국 포카 시장 시세 기준 (front AppRarity와 동기화) — 고레어만.
            -- 2026-05-12 사용자 확정 순서. ACE/H/R 등은 PokeFolio 미취급.
            ORDER BY CASE c.rarity_code
              WHEN 'MUR'  THEN 0  WHEN 'UR'   THEN 1
              WHEN 'SAR'  THEN 2  WHEN 'AR'   THEN 3
              WHEN 'MA'   THEN 4  WHEN 'BWR'  THEN 5
              WHEN 'CSR'  THEN 6  WHEN 'CHR'  THEN 7
              WHEN 'HR'   THEN 8  WHEN 'SSR'  THEN 9
              WHEN 'SR'   THEN 10 WHEN 'SM-P' THEN 11
              WHEN 'RRR'  THEN 12 WHEN 'RR'   THEN 13
              WHEN 'PR'   THEN 14 WHEN 'K'    THEN 15
              WHEN 'S'    THEN 16 ELSE 99 END ASC, c.name ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByRarityDesc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    // 등급 오름차순 (낮은 등급 → 높은 등급)
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            -- 한국 포카 시장 시세 기준 (front AppRarity와 동기화). DESC는 일반→정점 방향.
            -- 2026-05-12 사용자 확정 순서. ACE/H/R 등은 PokeFolio 미취급.
            ORDER BY CASE c.rarity_code
              WHEN 'MUR'  THEN 0  WHEN 'UR'   THEN 1
              WHEN 'SAR'  THEN 2  WHEN 'AR'   THEN 3
              WHEN 'MA'   THEN 4  WHEN 'BWR'  THEN 5
              WHEN 'CSR'  THEN 6  WHEN 'CHR'  THEN 7
              WHEN 'HR'   THEN 8  WHEN 'SSR'  THEN 9
              WHEN 'SR'   THEN 10 WHEN 'SM-P' THEN 11
              WHEN 'RRR'  THEN 12 WHEN 'RR'   THEN 13
              WHEN 'PR'   THEN 14 WHEN 'K'    THEN 15
              WHEN 'S'    THEN 16 ELSE 99 END DESC, c.name ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByRarityAsc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    // 날짜 내림차순 (최근 거래 먼저)
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            LEFT JOIN LATERAL (
                SELECT traded_at FROM price_snapshots
                WHERE card_id = c.card_id AND card_status = 'RAW'
                ORDER BY traded_at DESC LIMIT 1
            ) ps ON true
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY ps.traded_at DESC NULLS LAST, c.name ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByLatestDateDesc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    // 날짜 오름차순
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            LEFT JOIN LATERAL (
                SELECT traded_at FROM price_snapshots
                WHERE card_id = c.card_id AND card_status = 'RAW'
                ORDER BY traded_at DESC LIMIT 1
            ) ps ON true
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY ps.traded_at ASC NULLS LAST, c.name ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByLatestDateAsc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    // 이름순 ASC
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY c.name ASC, c.official_card_code ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByNameAsc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    // 이름순 DESC
    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
            AND c.rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY c.name DESC, c.official_card_code DESC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findByRarityOrderByNameDesc(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    @Query(nativeQuery = true, value = """
            SELECT COUNT(*)
            FROM cards
            WHERE (language = 'KO' OR is_promo_exclusive = TRUE)
            AND rarity_code IN (:rarityCodes)
            AND (:name = '' OR LOWER(name) LIKE LOWER(CONCAT('%', :name, '%')))
            """)
    long countByRarityAndName(
            @Param("rarityCodes") List<String> rarityCodes,
            @Param("name") String name);

    List<Card> findByCollectionNumberAndLanguage(String collectionNumber, String language);

    @Query(nativeQuery = true, value = """
            SELECT c.*
            FROM cards c
            LEFT JOIN LATERAL (
                SELECT COALESCE(
                  (SELECT price FROM price_snapshots WHERE card_id = c.card_id AND source = 'SCRYDEX_JP' AND card_status = 'RAW' ORDER BY traded_at DESC LIMIT 1),
                  (SELECT price FROM price_snapshots WHERE card_id = c.card_id AND source = 'SCRYDEX_JP' ORDER BY traded_at DESC, price ASC LIMIT 1)
                ) AS jp_price
            ) jp ON true
            LEFT JOIN LATERAL (
                SELECT price AS en_price FROM price_snapshots
                WHERE card_id = c.card_id AND source = 'SCRYDEX_EN' AND card_status = 'RAW'
                ORDER BY traded_at DESC LIMIT 1
            ) en ON true
            WHERE c.is_promo_exclusive = TRUE
              AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            ORDER BY COALESCE(jp.jp_price, en.en_price) DESC NULLS LAST, c.name ASC
            LIMIT :size OFFSET :offset
            """)
    List<Card> findPromoExclusiveOrderByPriceDesc(
            @Param("name") String name,
            @Param("size") int size,
            @Param("offset") int offset);

    @Query(nativeQuery = true, value = """
            SELECT COUNT(*) FROM cards c
            WHERE c.is_promo_exclusive = TRUE
              AND (:name = '' OR LOWER(c.name) LIKE LOWER(CONCAT('%', :name, '%')))
            """)
    long countPromoExclusive(@Param("name") String name);

    @Query(nativeQuery = true, value = """
            SELECT card_id, COALESCE(popularity_score, 0) AS popularity_score
            FROM cards
            WHERE card_id IN (:cardIds)
            """)
    List<Object[]> findPopularityScoresByCardIds(@Param("cardIds") List<String> cardIds);

    // KO_ESTIMATED 가장 최근 2개 날짜 자동 탐색.
    // 매일 매끄럽지 않을 수 있는 sync 패턴(scrydex 카드별 비동기 publish) 고려해서
    // CURRENT_DATE/CURRENT_DATE-1 하드코딩 대신 실제 데이터 있는 두 날짜 사용.
    // REFACTOR_2026-05-12.md 1차-C 참조.
    // 각 카드의 가장 최근 KO_ESTIMATED 2개를 비교한 변동률.
    // getMarketCards 응답에 카드별 dailyGainPct 채우는 용도. (REFACTOR_2026-05-12.md 4차-Round3)
    @Query(nativeQuery = true, value = """
            WITH last_two AS (
                SELECT card_id, traded_at, price,
                  ROW_NUMBER() OVER (PARTITION BY card_id ORDER BY traded_at DESC) AS rn
                FROM price_snapshots
                WHERE source = 'KO_ESTIMATED' AND card_id IN (:cardIds)
            )
            SELECT today.card_id,
                   today.price AS today_price,
                   yesterday.price AS yesterday_price,
                   ((today.price - yesterday.price) * 100.0 / NULLIF(yesterday.price, 0)) AS gain_pct
            FROM last_two today
            JOIN last_two yesterday ON yesterday.card_id = today.card_id
            WHERE today.rn = 1 AND yesterday.rn = 2
            """)
    List<Object[]> findKoDailyChangeByCardIds(@Param("cardIds") List<String> cardIds);

    @Query(nativeQuery = true, value = """
            WITH ko_dates AS (
                SELECT DISTINCT DATE(traded_at) AS d
                FROM price_snapshots
                WHERE source = 'KO_ESTIMATED'
                  AND DATE(traded_at) <= CURRENT_DATE
                ORDER BY d DESC
                LIMIT 2
            ),
            date_pair AS (
                SELECT
                    (SELECT d FROM ko_dates ORDER BY d DESC LIMIT 1) AS latest_day,
                    (SELECT d FROM ko_dates ORDER BY d DESC OFFSET 1 LIMIT 1) AS prev_day
            ),
            today AS (
                SELECT DISTINCT ON (ps.card_id)
                    ps.card_id, ps.price, ps.traded_at, ps.price_snapshot_id
                FROM price_snapshots ps, date_pair
                WHERE ps.source = 'KO_ESTIMATED'
                  AND DATE(ps.traded_at) = date_pair.latest_day
                ORDER BY ps.card_id, ps.traded_at DESC
            ),
            yesterday AS (
                SELECT DISTINCT ON (ps.card_id)
                    ps.card_id, ps.price, ps.traded_at
                FROM price_snapshots ps, date_pair
                WHERE ps.source = 'KO_ESTIMATED'
                  AND DATE(ps.traded_at) = date_pair.prev_day
                ORDER BY ps.card_id, ps.traded_at DESC
            )
            SELECT
                today.card_id,
                today.price AS today_price,
                yesterday.price AS yesterday_price,
                ((today.price - yesterday.price) * 100.0 / NULLIF(yesterday.price, 0)) AS gain_pct
            FROM today
            JOIN yesterday ON yesterday.card_id = today.card_id
            JOIN cards c ON c.card_id = today.card_id
            -- Turn D-1 (2026-05-17): audit INNER JOIN on ko_snapshot_id.
            -- ranking_eligible=true는 audit 14 reason 우선순위 모두 통과한 카드 (실제 raw 변동 확인).
            -- is_anomaly=false 중복이지만 명시적으로 두어 anomaly 카드 차단 보장.
            -- KREAM promo는 audit 미생성이므로 INNER JOIN으로 자연 제외.
            JOIN ko_estimation_audit a ON a.ko_snapshot_id = today.price_snapshot_id
            WHERE yesterday.price > 0
              AND (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
              AND a.ranking_eligible = true
              AND a.is_anomaly = false
              -- 보조 안전망 (audit 통과해도 추가 가드)
              AND today.price >= 5000
              AND yesterday.price >= 5000
              AND ABS(today.price - yesterday.price) >= 100
              AND ABS((today.price - yesterday.price) * 100.0 / yesterday.price) BETWEEN 0.1 AND 30.0
            ORDER BY gain_pct DESC, today.price DESC
            LIMIT :size
            """)
    List<Object[]> findTopGainersByKoEstimatedPrice(@Param("size") int size);

    // 급하락 — findTopGainers와 동일 SQL이지만 ORDER BY gain_pct ASC (음수 카드 우선).
    @Query(nativeQuery = true, value = """
            WITH ko_dates AS (
                SELECT DISTINCT DATE(traded_at) AS d
                FROM price_snapshots
                WHERE source = 'KO_ESTIMATED'
                  AND DATE(traded_at) <= CURRENT_DATE
                ORDER BY d DESC
                LIMIT 2
            ),
            date_pair AS (
                SELECT
                    (SELECT d FROM ko_dates ORDER BY d DESC LIMIT 1) AS latest_day,
                    (SELECT d FROM ko_dates ORDER BY d DESC OFFSET 1 LIMIT 1) AS prev_day
            ),
            today AS (
                SELECT DISTINCT ON (ps.card_id)
                    ps.card_id, ps.price, ps.traded_at, ps.price_snapshot_id
                FROM price_snapshots ps, date_pair
                WHERE ps.source = 'KO_ESTIMATED'
                  AND DATE(ps.traded_at) = date_pair.latest_day
                ORDER BY ps.card_id, ps.traded_at DESC
            ),
            yesterday AS (
                SELECT DISTINCT ON (ps.card_id)
                    ps.card_id, ps.price, ps.traded_at
                FROM price_snapshots ps, date_pair
                WHERE ps.source = 'KO_ESTIMATED'
                  AND DATE(ps.traded_at) = date_pair.prev_day
                ORDER BY ps.card_id, ps.traded_at DESC
            )
            SELECT
                today.card_id,
                today.price AS today_price,
                yesterday.price AS yesterday_price,
                ((today.price - yesterday.price) * 100.0 / NULLIF(yesterday.price, 0)) AS gain_pct
            FROM today
            JOIN yesterday ON yesterday.card_id = today.card_id
            JOIN cards c ON c.card_id = today.card_id
            -- Turn D-1 (2026-05-17): audit INNER JOIN on ko_snapshot_id.
            -- ranking_eligible=true는 audit 14 reason 우선순위 모두 통과한 카드 (실제 raw 변동 확인).
            -- is_anomaly=false 중복이지만 명시적으로 두어 anomaly 카드 차단 보장.
            -- KREAM promo는 audit 미생성이므로 INNER JOIN으로 자연 제외.
            JOIN ko_estimation_audit a ON a.ko_snapshot_id = today.price_snapshot_id
            WHERE yesterday.price > 0
              AND (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
              AND a.ranking_eligible = true
              AND a.is_anomaly = false
              -- 보조 안전망 (audit 통과해도 추가 가드)
              AND today.price >= 5000
              AND yesterday.price >= 5000
              AND ABS(today.price - yesterday.price) >= 100
              AND ABS((today.price - yesterday.price) * 100.0 / yesterday.price) BETWEEN 0.1 AND 30.0
            ORDER BY gain_pct ASC, today.price DESC
            LIMIT :size
            """)
    List<Object[]> findTopLosersByKoEstimatedPrice(@Param("size") int size);

    // 2026-06-03 급변동 재설계: KO 차트 투영과 동일 basis = JP(메인)/EN(브릿지) raw 시장 움직임.
    //   ko_estimation_audit(coef보정/FX/anomaly 섞임) 대신 SCRYDEX raw % 변동(N일 window).
    //   sanity band [3%, 40%] = raw outlier(0값/스파이크) 제외. 현재 KO 표시, prev = KO/(1+frac).
    //   응답 7 col: cardId, currentPrice, moveDatePrice, prevPrice, changeAmount, changePct, moveDate
    @Query(nativeQuery = true, value = """
            WITH jc AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_JP' AND card_status = 'RAW' AND raw_price > 0
                        ORDER BY card_id, traded_at DESC),
                 jp AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_JP' AND card_status = 'RAW' AND raw_price > 0
                          AND traded_at <= CURRENT_DATE - CAST(:days AS integer)
                        ORDER BY card_id, traded_at DESC),
                 ec AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_EN' AND card_status = 'RAW' AND raw_price > 0
                        ORDER BY card_id, traded_at DESC),
                 ep AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_EN' AND card_status = 'RAW' AND raw_price > 0
                          AND traded_at <= CURRENT_DATE - CAST(:days AS integer)
                        ORDER BY card_id, traded_at DESC),
                 ko AS (SELECT DISTINCT ON (card_id) card_id, price AS kp FROM price_snapshots
                        WHERE source = 'KO_ESTIMATED' ORDER BY card_id, traded_at DESC),
                 m AS (
                    SELECT c.card_id, ko.kp AS ck,
                           COALESCE((jc.rp - jp.rp) / NULLIF(jp.rp, 0), (ec.rp - ep.rp) / NULLIF(ep.rp, 0)) AS frac
                    FROM cards c JOIN ko ON ko.card_id = c.card_id
                    LEFT JOIN jc ON jc.card_id = c.card_id LEFT JOIN jp ON jp.card_id = c.card_id
                    LEFT JOIN ec ON ec.card_id = c.card_id LEFT JOIN ep ON ep.card_id = c.card_id
                    WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
                      AND c.is_visible = true
                      AND c.rarity_code NOT IN ('A', 'S', 'K')
                      AND ko.kp >= 5000
                 )
            SELECT card_id,
                   ck AS current_price,
                   ck AS move_date_price,
                   round(ck / (1 + frac)) AS prev_price,
                   round(ck - ck / (1 + frac)) AS change_amount,
                   round(frac * 100, 1) AS change_pct,
                   CURRENT_DATE AS move_date
            FROM m
            WHERE frac BETWEEN 0.03 AND 0.40 AND ABS(ck * frac) >= 100
              AND ck / (1 + frac) >= 5000
            ORDER BY frac DESC, ck DESC
            LIMIT :size
            """)
    List<Object[]> findRecentGainersByKoEstimatedPrice(@Param("days") int days, @Param("size") int size);

    @Query(nativeQuery = true, value = """
            WITH jc AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_JP' AND card_status = 'RAW' AND raw_price > 0
                        ORDER BY card_id, traded_at DESC),
                 jp AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_JP' AND card_status = 'RAW' AND raw_price > 0
                          AND traded_at <= CURRENT_DATE - CAST(:days AS integer)
                        ORDER BY card_id, traded_at DESC),
                 ec AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_EN' AND card_status = 'RAW' AND raw_price > 0
                        ORDER BY card_id, traded_at DESC),
                 ep AS (SELECT DISTINCT ON (card_id) card_id, raw_price AS rp FROM price_snapshots
                        WHERE source = 'SCRYDEX_EN' AND card_status = 'RAW' AND raw_price > 0
                          AND traded_at <= CURRENT_DATE - CAST(:days AS integer)
                        ORDER BY card_id, traded_at DESC),
                 ko AS (SELECT DISTINCT ON (card_id) card_id, price AS kp FROM price_snapshots
                        WHERE source = 'KO_ESTIMATED' ORDER BY card_id, traded_at DESC),
                 m AS (
                    SELECT c.card_id, ko.kp AS ck,
                           COALESCE((jc.rp - jp.rp) / NULLIF(jp.rp, 0), (ec.rp - ep.rp) / NULLIF(ep.rp, 0)) AS frac
                    FROM cards c JOIN ko ON ko.card_id = c.card_id
                    LEFT JOIN jc ON jc.card_id = c.card_id LEFT JOIN jp ON jp.card_id = c.card_id
                    LEFT JOIN ec ON ec.card_id = c.card_id LEFT JOIN ep ON ep.card_id = c.card_id
                    WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
                      AND c.is_visible = true
                      AND c.rarity_code NOT IN ('A', 'S', 'K')
                      AND ko.kp >= 5000
                 )
            SELECT card_id,
                   ck AS current_price,
                   ck AS move_date_price,
                   round(ck / (1 + frac)) AS prev_price,
                   round(ck - ck / (1 + frac)) AS change_amount,
                   round(frac * 100, 1) AS change_pct,
                   CURRENT_DATE AS move_date
            FROM m
            WHERE frac BETWEEN -0.40 AND -0.03 AND ABS(ck * frac) >= 100
              AND ck / (1 + frac) >= 5000
            ORDER BY frac ASC, ck DESC
            LIMIT :size
            """)
    List<Object[]> findRecentLosersByKoEstimatedPrice(@Param("days") int days, @Param("size") int size);

    // 인기 — card_interests COUNT desc. 관심 0인 카드도 포함 (LEFT JOIN), 일일 변동률 같이 반환.
    @Query(nativeQuery = true, value = """
            WITH interest_counts AS (
                SELECT card_id, COUNT(*) AS cnt
                FROM card_interests
                GROUP BY card_id
            ),
            ko_dates AS (
                SELECT DISTINCT DATE(traded_at) AS d
                FROM price_snapshots
                WHERE source = 'KO_ESTIMATED'
                  AND DATE(traded_at) <= CURRENT_DATE
                ORDER BY d DESC
                LIMIT 2
            ),
            date_pair AS (
                SELECT
                    (SELECT d FROM ko_dates ORDER BY d DESC LIMIT 1) AS latest_day,
                    (SELECT d FROM ko_dates ORDER BY d DESC OFFSET 1 LIMIT 1) AS prev_day
            ),
            today AS (
                SELECT DISTINCT ON (ps.card_id) ps.card_id, ps.price
                FROM price_snapshots ps, date_pair
                WHERE ps.source = 'KO_ESTIMATED'
                  AND DATE(ps.traded_at) = date_pair.latest_day
                ORDER BY ps.card_id, ps.traded_at DESC
            ),
            yesterday AS (
                SELECT DISTINCT ON (ps.card_id) ps.card_id, ps.price
                FROM price_snapshots ps, date_pair
                WHERE ps.source = 'KO_ESTIMATED'
                  AND DATE(ps.traded_at) = date_pair.prev_day
                ORDER BY ps.card_id, ps.traded_at DESC
            )
            SELECT
                c.card_id,
                COALESCE(today.price, 0) AS today_price,
                COALESCE(yesterday.price, 0) AS yesterday_price,
                CASE
                    WHEN yesterday.price IS NULL OR yesterday.price = 0 THEN 0
                    ELSE ((today.price - yesterday.price) * 100.0 / yesterday.price)
                END AS gain_pct,
                COALESCE(ic.cnt, 0) AS interest_count
            FROM cards c
            LEFT JOIN interest_counts ic ON ic.card_id = c.card_id
            JOIN today    ON today.card_id    = c.card_id        -- KO_ESTIMATED 있는 카드만
            LEFT JOIN yesterday ON yesterday.card_id = c.card_id
            WHERE (c.language = 'KO' OR c.is_promo_exclusive = TRUE)
              AND today.price > 0
            ORDER BY COALESCE(ic.cnt, 0) DESC, today.price DESC
            LIMIT :size
            """)
    List<Object[]> findPopularByInterestCount(@Param("size") int size);
}
