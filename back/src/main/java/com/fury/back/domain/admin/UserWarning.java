package com.fury.back.domain.admin;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 사용자 경고 — 신고 처리 결과로 admin 이 발급. 활성 경고 누적이 임계치 도달 시 자동 정지.
 * (suspend 는 binary 상태, warning 은 누적 카운트 + 감사 trail.)
 */
@Entity
@Table(name = "user_warnings")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class UserWarning {

    @Id
    @Column(name = "warning_id", length = 50)
    private String warningId;

    /** 경고 받은 유저. */
    @Column(name = "user_id", nullable = false, length = 50)
    private String userId;

    @Column(name = "reason", nullable = false, length = 200)
    private String reason;

    /** 근거 신고 id (있으면). */
    @Column(name = "report_id", length = 50)
    private String reportId;

    @Column(name = "issued_by", nullable = false, length = 50)
    private String issuedBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    /** 철회 시각 (admin 오발급 취소). null = 활성. */
    @Column(name = "revoked_at")
    private LocalDateTime revokedAt;

    @PrePersist
    void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now();
    }

    public void revoke() {
        this.revokedAt = LocalDateTime.now();
    }
}
