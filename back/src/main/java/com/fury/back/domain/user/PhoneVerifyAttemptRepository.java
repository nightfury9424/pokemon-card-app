package com.fury.back.domain.user;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;

public interface PhoneVerifyAttemptRepository extends JpaRepository<PhoneVerifyAttempt, String> {
    long countByPhoneE164AndCreatedAtAfter(String phoneE164, LocalDateTime after);
    long countByIpAndCreatedAtAfter(String ip, LocalDateTime after);
    long countByUserIdAndCreatedAtAfter(String userId, LocalDateTime after);
}
