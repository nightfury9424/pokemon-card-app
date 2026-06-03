package com.fury.back.domain.scanner;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

public interface ScanCaptureRepository extends JpaRepository<ScanCapture, String> {

    /** 카드당 캡처 수 (용량 cap 체크용 — 활성 row만). docs/IMAGE_DATA_STRATEGY.md cap ~20. */
    int countByCardIdAndDeletedAtIsNull(String cardId);

    /** 미인덱스 캡처 수 (admin 학습 버튼 상태 표시용). */
    long countByFaissIndexedFalseAndDeletedAtIsNull();

    /** 미인덱스 캡처 — 맥 agent 가 학습에 쓸 샘플 (S3 key 다운로드용). 오래된 것부터. */
    @Query("SELECT s FROM ScanCapture s WHERE s.faissIndexed = false AND s.deletedAt IS NULL ORDER BY s.createdAt ASC")
    List<ScanCapture> findUnindexed(Pageable pageable);

    /** 배포 시 — staged 인덱스에 포함된(=trained 시점 이전) 캡처를 indexed 마킹. */
    @Modifying
    @Query("UPDATE ScanCapture s SET s.faissIndexed = true "
            + "WHERE s.faissIndexed = false AND s.deletedAt IS NULL AND s.createdAt <= :before")
    int markIndexedBefore(@Param("before") LocalDateTime before);

    // ── FF2 커버리지 대시보드 (admin) ──

    /** 전체 활성 캡처 수. */
    long countByDeletedAtIsNull();

    /** 캡처가 1장 이상 쌓인 고유 카드 수 (수집 커버리지 분자). */
    @Query("SELECT COUNT(DISTINCT s.cardId) FROM ScanCapture s WHERE s.deletedAt IS NULL")
    long countDistinctCardsCovered();

    /** cap(=20) 도달한 카드 수 — 더 모을 필요 없는 카드. */
    @Query(value = "SELECT COUNT(*) FROM (SELECT card_id FROM scan_captures "
            + "WHERE deleted_at IS NULL GROUP BY card_id HAVING COUNT(*) >= :cap) t", nativeQuery = true)
    long countCardsAtCap(@Param("cap") int cap);

    /** 캡처 많은 순 top N (card_id, name, count) — 진행 현황 확인용. */
    @Query(value = "SELECT s.card_id, c.name, COUNT(*) AS cnt FROM scan_captures s "
            + "LEFT JOIN cards c ON c.card_id = s.card_id "
            + "WHERE s.deleted_at IS NULL GROUP BY s.card_id, c.name ORDER BY cnt DESC LIMIT :limit",
            nativeQuery = true)
    List<Object[]> topCardsByCaptureCount(@Param("limit") int limit);
}
