package com.fury.back.domain.board;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

public interface BoardImageUploadRepository extends JpaRepository<BoardImageUpload, String> {

    List<BoardImageUpload> findAllByUploadIdIn(Collection<String> uploadIds);

    /** 사용자별 활성(미만료) PENDING 개수 — 만료분은 제외(곧 정리됨). pending 제한용. */
    long countByUploaderIdAndStatusAndExpiresAtAfter(String uploaderId, String status, LocalDateTime now);

    /** 빈도 제한 — 최근 window 내 업로드 수(PENDING/CONSUMED 무관). */
    long countByUploaderIdAndCreatedAtAfter(String uploaderId, LocalDateTime since);

    /** 만료 정리 cron — status=PENDING AND expires_at < now. (S3 삭제 성공 후에만 행 삭제) */
    List<BoardImageUpload> findTop200ByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(String status, LocalDateTime now);
}
