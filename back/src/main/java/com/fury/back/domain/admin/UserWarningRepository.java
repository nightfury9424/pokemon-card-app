package com.fury.back.domain.admin;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface UserWarningRepository extends JpaRepository<UserWarning, String> {

    /** 활성 경고 수 (임계치 비교용). */
    long countByUserIdAndRevokedAtIsNull(String userId);

    /** 유저 활성 경고 목록 (최신순). */
    List<UserWarning> findByUserIdAndRevokedAtIsNullOrderByCreatedAtDesc(String userId);
}
