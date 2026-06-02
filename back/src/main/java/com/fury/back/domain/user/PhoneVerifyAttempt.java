package com.fury.back.domain.user;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * 휴대폰 OTP 발송 요청 기록 — 휴대폰/IP/계정별 rate limit 의 진실원.
 * Firebase 가 SMS 발송 quota 를 갖지만 클라→Firebase 직접 호출이라 우리가 못 봄 →
 * 발송 직전 /phone/request-otp 로 우리 측에서 한 번 더 strict 가드(DB 영속).
 */
@Entity
@Table(name = "phone_verify_attempts")
@Getter
@NoArgsConstructor(access = AccessLevel.PROTECTED)
@AllArgsConstructor
@Builder
public class PhoneVerifyAttempt {

    @Id
    @Column(name = "attempt_id", length = 50)
    private String attemptId;

    @Column(name = "phone_e164", nullable = false, length = 20)
    private String phoneE164;

    @Column(name = "user_id", length = 50)
    private String userId;

    @Column(name = "ip", length = 64)
    private String ip;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    void onCreate() {
        this.createdAt = LocalDateTime.now();
    }
}
