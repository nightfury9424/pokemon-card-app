package com.fury.back.domain.inquiry;

import org.springframework.data.jpa.repository.JpaRepository;

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
}
