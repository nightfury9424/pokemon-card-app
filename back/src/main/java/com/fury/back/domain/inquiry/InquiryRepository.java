package com.fury.back.domain.inquiry;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface InquiryRepository extends JpaRepository<Inquiry, String> {

    /** 내 문의 내역 (최신순). */
    List<Inquiry> findByUserIdOrderByCreatedAtDesc(String userId);

    /** 관리자 — 전체 문의 (최신순). */
    List<Inquiry> findAllByOrderByCreatedAtDesc();

    /** 관리자 — 상태별 (최신순). */
    List<Inquiry> findByStatusOrderByCreatedAtDesc(String status);

    long countByStatus(String status);

    /** 정지 이의신청 중복 방지 — 같은 유저의 OPEN 상태 이의신청 존재 여부. */
    boolean existsByUserIdAndCategoryAndStatus(String userId, String category, String status);

    /**
     * 정지 이의신청 중복 방지(현재 정지건 한정) — createdAt 이 현재 정지 시각 이후인 OPEN 이의신청만 카운트.
     * 과거 정지 때 만든 묵은 이의신청이 새 정지건 이의신청을 막던 버그 fix.
     */
    boolean existsByUserIdAndCategoryAndStatusAndCreatedAtGreaterThanEqual(
            String userId, String category, String status, LocalDateTime createdAt);

    /** 정지 해제 시 자동 종료할 OPEN 이의신청 조회. */
    List<Inquiry> findByUserIdAndCategoryAndStatus(String userId, String category, String status);
}
