package com.fury.back.domain.price.sync;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDate;
import java.time.OffsetDateTime;

@Entity
@Table(name = "price_sync_runs")
@Getter
@Setter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PriceSyncRun {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "job_name", nullable = false, length = 50)
    private String jobName;

    @Column(name = "business_date", nullable = false)
    private LocalDate businessDate;

    @Enumerated(EnumType.STRING)
    @Column(name = "status", nullable = false, length = 20)
    private SyncRunStatus status;

    @Enumerated(EnumType.STRING)
    @Column(name = "trigger_source", nullable = false, length = 20)
    private TriggerSource triggerSource;

    @Column(name = "scheduled_at", nullable = false)
    private OffsetDateTime scheduledAt;

    @Column(name = "started_at", nullable = false)
    private OffsetDateTime startedAt;

    @Column(name = "ended_at")
    private OffsetDateTime endedAt;

    @Column(name = "row_count_en")
    private Integer rowCountEn;

    @Column(name = "row_count_jp")
    private Integer rowCountJp;

    @Column(name = "retry_count", nullable = false)
    private Integer retryCount;

    @Column(name = "error_message", columnDefinition = "TEXT")
    private String errorMessage;

    @Column(name = "notified_at")
    private OffsetDateTime notifiedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private OffsetDateTime createdAt;
}
