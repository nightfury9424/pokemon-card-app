package com.fury.back.domain.price.sync;

import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDate;
import java.util.Optional;

public interface PriceSyncRunRepository
        extends JpaRepository<PriceSyncRun, Long>, PriceSyncRunRepositoryCustom {

    Optional<PriceSyncRun> findByJobNameAndBusinessDate(String jobName, LocalDate businessDate);
}
