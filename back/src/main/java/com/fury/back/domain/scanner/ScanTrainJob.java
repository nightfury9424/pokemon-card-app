package com.fury.back.domain.scanner;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;
import java.util.UUID;

/**
 * 스캔 모델 재학습 job (docs/IMAGE_DATA_STRATEGY.md FF1) — 메타몽식 맥북 agent 오케스트레이션.
 * 무중단 blue-green: 학습 중 서버는 OLD 인덱스 서빙, TRAINED 후 명시적 DEPLOY 시에만 원자 스왑.
 */
@Entity
@Table(name = "scan_train_jobs")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class ScanTrainJob {

    /** REQUESTED → TRAINING → TRAINED → DEPLOYING → DEPLOYED / FAILED */
    public enum Status { REQUESTED, TRAINING, TRAINED, DEPLOYING, DEPLOYED, FAILED }

    @Id
    @Column(name = "job_id", length = 50)
    private String jobId;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private Status status;

    @Column(name = "staged_index_key", columnDefinition = "TEXT")
    private String stagedIndexKey;

    @Column(name = "sample_count")
    private Integer sampleCount;

    @Column(name = "message", columnDefinition = "TEXT")
    private String message;

    @Column(name = "requested_by", length = 50)
    private String requestedBy;

    @Column(name = "requested_at", nullable = false, updatable = false)
    private LocalDateTime requestedAt;

    @Column(name = "trained_at")
    private LocalDateTime trainedAt;

    @Column(name = "deployed_at")
    private LocalDateTime deployedAt;

    @PrePersist
    void onCreate() {
        if (requestedAt == null) requestedAt = LocalDateTime.now();
    }

    public static ScanTrainJob request(String adminUserId) {
        return ScanTrainJob.builder()
                .jobId("STRN_" + UUID.randomUUID().toString().replace("-", "").substring(0, 24).toUpperCase())
                .status(Status.REQUESTED)
                .requestedBy(adminUserId)
                .build();
    }

    /** 비-종결 상태 (새 학습 요청 중복 방지용). */
    public boolean isActive() {
        return status == Status.REQUESTED || status == Status.TRAINING
                || status == Status.TRAINED || status == Status.DEPLOYING;
    }
}
