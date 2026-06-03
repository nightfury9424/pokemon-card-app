package com.fury.back.domain.scanner;

import com.fury.back.storage.ImageStorageService;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Base64;

/**
 * 스캔 캡처 수집 (docs/IMAGE_DATA_STRATEGY.md Phase 1).
 * 스캔 성공 시 스캐너가 반환한 warp-crop(base64)을 S3 + scan_captures 에 비동기 저장.
 * 용도: FAISS multi-ref 보강(매칭) + 카탈로그 이미지 교체(scrydex moat). 품질지표는 서버 배치(FF1)로 후채움.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ScanCaptureService {

    private final ScanCaptureRepository repository;
    private final ImageStorageService imageStorage;

    /** 카드당 캡처 상한 — 무한 증식 차단(유저수 무관 상한 고정). */
    private static final int PER_CARD_CAP = 20;
    /** ToS 일괄동의 버전 스냅샷(PIPA). ToS 개정 시 갱신. */
    private static final String CONSENT_VERSION = "2026-06-03";

    /**
     * fire-and-forget. 스캔 응답을 블로킹하지 않음. cap 초과/디코드·저장 실패는 조용히 skip
     * (수집은 best-effort, 스캔 UX 영향 0).
     */
    @Async
    @Transactional
    public void captureAsync(String cardId, String userId, String cropB64, Float confidence) {
        if (cardId == null || cropB64 == null || cropB64.isBlank()) return;
        try {
            // 카드당 cap — 인기 카드 무한 증식 차단.
            if (repository.countByCardIdAndDeletedAtIsNull(cardId) >= PER_CARD_CAP) {
                log.debug("[ScanCapture] cap({}) reached card={} — skip", PER_CARD_CAP, cardId);
                return;
            }
            byte[] bytes = Base64.getDecoder().decode(cropB64);
            String key = imageStorage.store("uploads/scan/" + cardId, "scan.jpg", bytes, "image/jpeg");
            repository.save(ScanCapture.ofScan(cardId, key, userId, confidence, CONSENT_VERSION));
            log.info("[ScanCapture] saved card={} user={} key={} ({}B)", cardId, userId, key, bytes.length);
        } catch (Exception e) {
            log.warn("[ScanCapture] capture skipped card={}: {}", cardId, e.getMessage());
        }
    }
}
