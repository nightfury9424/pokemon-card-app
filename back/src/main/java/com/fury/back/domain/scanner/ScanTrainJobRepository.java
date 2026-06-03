package com.fury.back.domain.scanner;

import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface ScanTrainJobRepository extends JpaRepository<ScanTrainJob, String> {

    /** 최신 job (admin 상태 표시 + 버튼 게이팅용). */
    Optional<ScanTrainJob> findFirstByOrderByRequestedAtDesc();

    /** 특정 상태 job들 (agent claim=REQUESTED, deploy=TRAINED 조회). */
    List<ScanTrainJob> findByStatusOrderByRequestedAtAsc(ScanTrainJob.Status status);
}
