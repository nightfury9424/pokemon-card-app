package com.fury.back.domain.board;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

public interface BoardImageUploadRepository extends JpaRepository<BoardImageUpload, String> {

    List<BoardImageUpload> findAllByUploadIdIn(Collection<String> uploadIds);

    /** 사용자별 미소비 pending 개수 제한용. */
    long countByUploaderIdAndStatus(String uploaderId, String status);

    /** 만료 정리 cron — status=PENDING AND expires_at < now. (S3 삭제 성공 후에만 행 삭제) */
    List<BoardImageUpload> findTop200ByStatusAndExpiresAtBeforeOrderByExpiresAtAsc(String status, LocalDateTime now);
}
