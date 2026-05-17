package com.fury.back.domain.report;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

@Entity
@Table(name = "reports")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class Report {

    @Id
    @Column(name = "report_id", length = 50)
    private String reportId;

    @Column(name = "reporter_id", nullable = false, length = 50)
    private String reporterId;

    /** TRADE / USER / BUY_ORDER / CHAT */
    @Column(name = "target_type", nullable = false, length = 20)
    private String targetType;

    @Column(name = "target_id", nullable = false, length = 50)
    private String targetId;

    /** FRAUD / FAKE / ABUSIVE_PRICE / INSULT / SPAM / OTHER */
    @Column(name = "reason", nullable = false, length = 40)
    private String reason;

    @Column(name = "detail", columnDefinition = "TEXT")
    private String detail;

    /** PENDING / REVIEWED / RESOLVED / DISMISSED */
    @Column(name = "status", nullable = false, length = 20)
    private String status;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "reviewed_at")
    private LocalDateTime reviewedAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
        if (status == null) status = "PENDING";
    }
}
