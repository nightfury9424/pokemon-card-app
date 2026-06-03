package com.fury.back.domain.scanner;

import org.springframework.data.jpa.repository.JpaRepository;

public interface ScanCaptureRepository extends JpaRepository<ScanCapture, String> {

    /** 카드당 캡처 수 (용량 cap 체크용 — 활성 row만). docs/IMAGE_DATA_STRATEGY.md cap ~20. */
    int countByCardIdAndDeletedAtIsNull(String cardId);
}
