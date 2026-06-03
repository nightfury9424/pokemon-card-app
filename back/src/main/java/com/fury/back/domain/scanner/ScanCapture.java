package com.fury.back.domain.scanner;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * 스캔 캡처 — 유저가 스캔 성공 시 warp-crop 된 카드 이미지 1장 (docs/IMAGE_DATA_STRATEGY.md).
 * 한 번의 스캔이 (A)한국 카드 실사진 + (B)스캔 라벨 데이터 둘 다 생성.
 * 용도: FAISS multi-ref 보강(매칭) + 카탈로그 이미지 교체(scrydex moat). 품질지표는 서버 배치로 후채움.
 */
@Entity
@Table(name = "scan_captures")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class ScanCapture {

    @Id
    @Column(name = "capture_id", length = 50)
    private String captureId;

    @Column(name = "user_id", length = 50)
    private String userId;

    @Column(name = "card_id", nullable = false, length = 50)
    private String cardId;

    @Column(name = "s3_key", nullable = false, columnDefinition = "TEXT")
    private String s3Key;

    @Column(name = "source_type", nullable = false, length = 20)
    private String sourceType;

    @Column(name = "match_confidence")
    private Float matchConfidence;

    /** NULL = 미평가. 0~100. 저장 후 서버 배치(FF1)가 채움. */
    @Column(name = "image_quality")
    private Short imageQuality;

    @Column(name = "blur_score")
    private Float blurScore;

    @Column(name = "is_catalog_candidate", nullable = false)
    private boolean catalogCandidate;

    @Column(name = "is_faiss_indexed", nullable = false)
    private boolean faissIndexed;

    @Column(name = "consent_version", length = 16)
    private String consentVersion;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }

    /** 스캔 성공 캡처 생성. 품질지표는 NULL(배치 후채움), 플래그 false. */
    public static ScanCapture ofScan(String cardId, String s3Key, String userId,
                                     Float matchConfidence, String consentVersion) {
        return ScanCapture.builder()
                .captureId("SCAP_" + UUID.randomUUID().toString().replace("-", "").substring(0, 24).toUpperCase())
                .cardId(cardId)
                .s3Key(s3Key)
                .userId(userId)
                .sourceType("SCAN")
                .matchConfidence(matchConfidence)
                .catalogCandidate(false)
                .faissIndexed(false)
                .consentVersion(consentVersion)
                .build();
    }
}
