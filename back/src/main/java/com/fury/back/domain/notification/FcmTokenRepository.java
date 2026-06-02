package com.fury.back.domain.notification;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface FcmTokenRepository extends JpaRepository<FcmToken, String> {
    Optional<FcmToken> findByToken(String token);
    List<FcmToken> findByUserId(String userId);
    void deleteByToken(String token);
    void deleteByUserId(String userId);
}
