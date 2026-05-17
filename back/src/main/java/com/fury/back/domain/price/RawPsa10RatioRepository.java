package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface RawPsa10RatioRepository
        extends JpaRepository<RawPsa10Ratio, RawPsa10Ratio.PK> {

    Optional<RawPsa10Ratio> findBySourceAndRarityCode(String source, String rarityCode);

    List<RawPsa10Ratio> findAllByOrderBySourceAscRarityCodeAsc();

    /**
     * 14일/30일 윈도우로 카드별 RAW/PSA10 페어 + 비율 산출.
     * RAW < PSA10, 가격 >= 1000원, raw·psa10 모두 최근 N일 내 거래만.
     * 결과는 카드별 1 row — (source, rarity_code, raw, psa10, ratio).
     */
    @Query(value = """
        WITH latest_raw AS (
          SELECT DISTINCT ON (ps.card_id, ps.source)
                 ps.card_id, ps.source, ps.price AS raw_price, ps.traded_at
            FROM price_snapshots ps
           WHERE ps.source IN ('SCRYDEX_JP','SCRYDEX_EN')
             AND ps.card_status = 'RAW'
             AND ps.traded_at >= NOW() - (:windowDays || ' days')::interval
           ORDER BY ps.card_id, ps.source, ps.traded_at DESC
        ),
        latest_psa10 AS (
          SELECT DISTINCT ON (ps.card_id, ps.source)
                 ps.card_id, ps.source, ps.price AS psa10_price, ps.traded_at
            FROM price_snapshots ps
           WHERE ps.source IN ('SCRYDEX_JP','SCRYDEX_EN')
             AND ps.card_status = 'GRADED'
             AND ps.grading_company = 'PSA'
             AND ps.grade_value = '10'
             AND ps.traded_at >= NOW() - (:windowDays || ' days')::interval
           ORDER BY ps.card_id, ps.source, ps.traded_at DESC
        )
        SELECT r.source                                                  AS source,
               COALESCE(NULLIF(c.rarity_code,''), 'UNKNOWN')             AS rarity_code,
               (r.raw_price::numeric / NULLIF(p.psa10_price, 0))         AS ratio
          FROM latest_raw r
          JOIN latest_psa10 p ON r.card_id = p.card_id AND r.source = p.source
          JOIN cards c        ON c.card_id = r.card_id
         WHERE r.raw_price > 0
           AND p.psa10_price > 0
           AND r.raw_price < p.psa10_price
           AND r.raw_price >= 1000
        """, nativeQuery = true)
    List<Object[]> findPairsForRatio(@Param("windowDays") int windowDays);
}
