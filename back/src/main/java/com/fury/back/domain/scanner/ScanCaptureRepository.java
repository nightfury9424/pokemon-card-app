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
}
