package com.fury.back.domain.user;

import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

public interface DeletedUserAuditRepository extends JpaRepository<DeletedUserAudit, String> {

    /** purge 대상 — purgeAfter 경과(오래된 것부터). Pageable 로 배치 크기 제한. */
    List<DeletedUserAudit> findByPurgeAfterBeforeOrderByPurgeAfterAsc(LocalDateTime now, Pageable pageable);
}
