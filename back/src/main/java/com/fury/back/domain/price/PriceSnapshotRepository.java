package com.fury.back.domain.price;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

public interface PriceSnapshotRepository extends JpaRepository<PriceSnapshot, String> {
    List<PriceSnapshot> findByCardIdOrderByTradedAtDesc(String cardId);

    List<PriceSnapshot> findByCardIdAndTradedAtAfterOrderByTradedAtDesc(String cardId, LocalDateTime after);

    List<PriceSnapshot> findByCardIdInAndCardStatusOrderByTradedAtDesc(List<String> cardIds, String cardStatus);

    // 해외 시세 (TCGPLAYER source)
    List<PriceSnapshot> findByCardIdAndSourceOrderByTradedAtDesc(String cardId, String source);

    // 해외 시세 복수 소스 (SCRYDEX_JP, SCRYDEX_EN 등)
    List<PriceSnapshot> findByCardIdAndSourceInAndCardStatusOrderByTradedAtDesc(
            String cardId, List<String> sources, String cardStatus);

    // 계수 계산용: 특정 source가 아닌 스냅샷 (한국 시세만)
    @Query("SELECT ps FROM PriceSnapshot ps WHERE ps.cardId IN :cardIds AND ps.source != :excludeSource AND ps.cardStatus = 'RAW' AND ps.tradedAt > :after")
    List<PriceSnapshot> findKoreanPrices(
            @Param("cardIds") List<String> cardIds,
            @Param("excludeSource") String excludeSource,
            @Param("after") LocalDateTime after);

    // 계수 계산용: TCGPLAYER 스냅샷
    @Query("SELECT ps FROM PriceSnapshot ps WHERE ps.cardId IN :cardIds AND ps.source = :source AND ps.tradedAt > :after")
    List<PriceSnapshot> findGlobalPrices(
            @Param("cardIds") List<String> cardIds,
            @Param("source") String source,
            @Param("after") LocalDateTime after);

    // 중복 저장 방지: 같은 날 같은 카드의 TCGPLAYER 스냅샷 존재 여부
    boolean existsByCardIdAndSourceAndTradedAtAfter(String cardId, String source, LocalDateTime after);
}
